package core

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"sync/atomic"
	"testing"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"go.yaml.in/yaml/v3"
)

func productFixture(t *testing.T, name string) []byte {
	t.Helper()
	dir := os.Getenv("FLASHCO_CORE_FIXTURE_DIR")
	if dir == "" {
		t.Skip("FLASHCO_CORE_FIXTURE_DIR is unset; run profile_core_fixture_test.dart with REALITY_SUPPORT_X25519MLKEM768=true first")
	}
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func closeProductConfig(t *testing.T, cfg *config.Config) {
	t.Helper()
	t.Cleanup(func() {
		for _, p := range cfg.Providers {
			if closer, ok := p.(io.Closer); ok {
				_ = closer.Close()
			}
		}
		for _, p := range cfg.Proxies {
			_ = p.Close()
		}
	})
}

func TestProductProfile350Nodes(t *testing.T) {
	data := productFixture(t, "fallback-350.yaml")
	withSpillHome(t, responseSpillThreshold)
	cfg, err := loadConfig(writeBaseProfile(t, string(data)))
	if err != nil {
		t.Fatalf("pinned Core rejected the final Dart profile: %v", err)
	}
	closeProductConfig(t, cfg)
	for i := 1; i <= 350; i++ {
		name := fmt.Sprintf("node-%d", i)
		if p := cfg.Proxies[name]; p == nil || p.Type() != C.Vless {
			t.Fatalf("node %q was lost or failed to parse: %v", name, p)
		}
	}
	group := cfg.Proxies["Flashco fallback"]
	if group == nil || group.Type() != C.Fallback {
		t.Fatalf("expected the native Fallback group, got %v", group)
	}
	serialized, err := group.MarshalJSON()
	if err != nil {
		t.Fatal(err)
	}
	var state struct {
		All           []string `json:"all"`
		Now           string   `json:"now"`
		EmptyFallback string   `json:"emptyFallback"`
	}
	if err := json.Unmarshal(serialized, &state); err != nil {
		t.Fatal(err)
	}
	if len(state.All) != 350 || state.Now != "node-1" || state.EmptyFallback != "REJECT" {
		t.Fatalf("unexpected fallback count/priority/empty behavior: %+v", state)
	}
	for i, name := range state.All {
		if name != fmt.Sprintf("node-%d", i+1) {
			t.Fatalf("fallback priority changed at %d: %q", i, name)
		}
	}
	if got := ruleStrings(cfg); !reflect.DeepEqual(got, []string{"Domain,example.invalid,DIRECT", "Match,,PROXY"}) {
		t.Fatalf("final rule order changed: %v", got)
	}

}

func TestProductProfileEmptyFallback(t *testing.T) {
	// A real provider whose only node is excluded by the final profile's type
	// filter must remain closed instead of inserting DIRECT into the group.
	data := productFixture(t, "empty-provider.yaml")
	withSpillHome(t, responseSpillThreshold)
	empty, err := loadConfig(writeBaseProfile(t, string(data)))
	if err != nil {
		t.Fatal(err)
	}
	closeProductConfig(t, empty)
	if got := empty.Proxies["Flashco fallback"].Unwrap(nil, false).Name(); got != "REJECT" {
		t.Fatalf("empty fallback selected %q, want REJECT", got)
	}
}

func TestProductProfileProviderRefresh(t *testing.T) {
	data := productFixture(t, "provider-refresh.yaml")
	for _, kind := range []string{"inline", "file", "http"} {
		t.Run(kind, func(t *testing.T) {
			home := withSpillHome(t, responseSpillThreshold)
			var raw map[string]any
			if err := yaml.Unmarshal(data, &raw); err != nil {
				t.Fatal(err)
			}
			mapping := raw["proxy-providers"].(map[string]any)["subscription"].(map[string]any)
			payload := mapping["payload"]
			source, err := yaml.Marshal(map[string]any{"proxies": payload})
			if err != nil {
				t.Fatal(err)
			}
			mapping["type"] = kind
			mapping["health-check"] = map[string]any{"enable": false}
			path := filepath.Join(home, kind+".yaml")
			var served atomic.Value
			served.Store(source)
			if kind != "inline" {
				delete(mapping, "payload")
				mapping["path"] = path
			}
			if kind == "file" {
				if err := os.WriteFile(path, source, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			if kind == "http" {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					_, _ = w.Write(served.Load().([]byte))
				}))
				t.Cleanup(server.Close)
				mapping["url"] = server.URL
			}
			p, err := provider.ParseProxyProvider("subscription", mapping, nil)
			if err != nil {
				t.Fatalf("parse %s provider: %v", kind, err)
			}
			t.Cleanup(func() {
				if closer, ok := p.(io.Closer); ok {
					_ = closer.Close()
				}
			})
			if err := p.Initial(); err != nil {
				t.Fatalf("initialize %s provider: %v", kind, err)
			}
			assertProductRealityProxies(t, p, "")
			version := p.Version()
			if kind != "inline" {
				// New subscription content exercises the real Fetcher/Vehicle and
				// parser again; no mock or direct OverrideExpr.Apply call is used.
				source = bytes.ReplaceAll(source, []byte("name: "), []byte("name: refreshed-"))
				if kind == "file" {
					if err := os.WriteFile(path, source, 0o600); err != nil {
						t.Fatal(err)
					}
				} else {
					served.Store(source)
				}
			}
			if err := p.Update(); err != nil {
				t.Fatalf("refresh %s provider: %v", kind, err)
			}
			if kind == "inline" {
				assertProductRealityProxies(t, p, "")
			} else {
				assertProductRealityProxies(t, p, "refreshed-")
				if p.Version() <= version {
					t.Fatal("provider version did not advance after changed subscription")
				}
				stored, err := os.ReadFile(path)
				if err != nil || !bytes.Equal(stored, source) {
					t.Fatalf("defaults modified the subscription source/cache: %v", err)
				}
			}
		})
	}
}

func assertProductRealityProxies(t *testing.T, p P.ProxyProvider, prefix string) {
	t.Helper()
	if p.Count() != 3 {
		t.Fatalf("provider count = %d, want 3", p.Count())
	}
	wants := []struct {
		name        string
		mlkem       bool
		fingerprint string
	}{
		{"missing", true, "chrome"},
		{"explicit-false", false, "firefox"},
		{"explicit-true", true, "chrome120"},
	}
	for i, proxy := range p.Proxies() {
		want := wants[i]
		if proxy.Name() != "Saved "+prefix+want.name || !proxy.SupportUDP() {
			t.Fatalf("existing provider overrides/order were lost: %s, udp=%v", proxy.Name(), proxy.SupportUDP())
		}
		adapter := proxy.Adapter()
		// Provider nodes are wrapped in the Core's automatic resource owner.
		if wrapped := reflect.ValueOf(adapter).Elem().FieldByName("ProxyAdapter"); wrapped.IsValid() {
			adapter = wrapped.Interface().(C.ProxyAdapter)
		}
		vless, ok := adapter.(*outbound.Vless)
		if !ok {
			t.Fatalf("expected a parsed VLESS adapter, got %T", proxy.Adapter())
		}
		// The pinned adapter exposes neither its fingerprint nor REALITY flag
		// publicly. Read the effective parsed options without unsafe or mutation.
		option := reflect.ValueOf(vless).Elem().FieldByName("option").Elem()
		reality := option.FieldByName("RealityOpts")
		if got := reality.FieldByName("SupportX25519MLKEM768").Bool(); got != want.mlkem {
			t.Errorf("%s ML-KEM = %v, want %v", proxy.Name(), got, want.mlkem)
		}
		if got := option.FieldByName("ClientFingerprint").String(); got != want.fingerprint {
			t.Errorf("%s fingerprint = %q, want %q", proxy.Name(), got, want.fingerprint)
		}
	}
}
