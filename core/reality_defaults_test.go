package core

import (
	"encoding/json"
	"os"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/adapter/provider"
)

func TestRealityMlkemProviderDefaults(t *testing.T) {
	path := os.Getenv("REALITY_MLKEM_FIXTURE_PATH")
	if path == "" {
		t.Skip("REALITY_MLKEM_FIXTURE_PATH is not set; generated provider expressions are unavailable")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read generated provider expressions: %v", err)
	}
	var sources []string
	if err := json.Unmarshal(data, &sources); err != nil {
		t.Fatalf("decode generated provider expressions: %v", err)
	}
	if len(sources) != 3 || sources[0] != ".udp = true" {
		t.Fatalf("expected existing UDP expression followed by two defaults, got %q", sources)
	}
	var expressions []provider.OverrideExpr
	for _, source := range sources {
		expression, err := provider.NewOverrideExpr(source)
		if err != nil {
			t.Fatalf("compile provider expression %q: %v", source, err)
		}
		expressions = append(expressions, expression)
	}

	cases := []struct {
		name  string
		input string
		want  string
	}{
		{"missing defaults", `{"type":"vless","name":"one","server":"example.org","reality-opts":{"public-key":"key","short-id":"id","other":"kept"}}`, `{"type":"vless","name":"one","server":"example.org","udp":true,"client-fingerprint":"chrome","reality-opts":{"public-key":"key","short-id":"id","other":"kept","support-x25519mlkem768":true}}`},
		{"explicit false and firefox", `{"reality-opts":{"public-key":"key","support-x25519mlkem768":false},"client-fingerprint":"firefox"}`, `{"udp":true,"reality-opts":{"public-key":"key","support-x25519mlkem768":false},"client-fingerprint":"firefox"}`},
		{"explicit true and empty fingerprint", `{"reality-opts":{"public-key":"key","support-x25519mlkem768":true},"client-fingerprint":""}`, `{"udp":true,"reality-opts":{"public-key":"key","support-x25519mlkem768":true},"client-fingerprint":""}`},
		{"explicit null and none fingerprint", `{"reality-opts":{"public-key":"key","support-x25519mlkem768":null},"client-fingerprint":"none"}`, `{"udp":true,"reality-opts":{"public-key":"key","support-x25519mlkem768":null},"client-fingerprint":"none"}`},
		{"null fingerprint", `{"reality-opts":{"public-key":"key"},"client-fingerprint":null}`, `{"udp":true,"reality-opts":{"public-key":"key","support-x25519mlkem768":true},"client-fingerprint":null}`},
		{"no reality options", `{"type":"trojan","name":"plain"}`, `{"type":"trojan","name":"plain","udp":true}`},
		{"null reality options", `{"reality-opts":null}`, `{"reality-opts":null,"udp":true}`},
		{"non-map reality options", `{"reality-opts":"invalid"}`, `{"reality-opts":"invalid","udp":true}`},
		{"missing public key", `{"reality-opts":{"short-id":"id"}}`, `{"reality-opts":{"short-id":"id"},"udp":true}`},
		{"empty public key", `{"reality-opts":{"public-key":""}}`, `{"reality-opts":{"public-key":""},"udp":true}`},
		{"non-string public key", `{"reality-opts":{"public-key":42}}`, `{"reality-opts":{"public-key":42},"udp":true}`},
		{"null public key", `{"reality-opts":{"public-key":null}}`, `{"reality-opts":{"public-key":null},"udp":true}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var input, want map[string]any
			if err := json.Unmarshal([]byte(tc.input), &input); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal([]byte(tc.want), &want); err != nil {
				t.Fatal(err)
			}
			for _, expression := range expressions {
				if err := expression.Apply(input); err != nil {
					t.Fatalf("apply provider expression %q: %v", expression.String(), err)
				}
			}
			if !reflect.DeepEqual(input, want) {
				t.Errorf("got %#v; want %#v", input, want)
			}
		})
	}
}
