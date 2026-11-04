package core

import (
	"testing"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
)

type pairHealthProxy struct {
	C.Proxy
	alive bool
}

func (p *pairHealthProxy) AliveForTestUrl(string) bool { return p.alive }

func TestProfileNodePairFallsBackAndReturnsToPrimary(t *testing.T) {
	primary := &pairHealthProxy{Proxy: namedProxy("primary"), alive: true}
	backup := &pairHealthProxy{Proxy: namedProxy("backup"), alive: true}
	members := []C.Proxy{primary, backup}
	health := provider.NewHealthCheck(members, "https://probe.invalid", 0, 0, true, nil)
	pd, err := provider.NewCompatibleProvider("pair-members", members, health)
	if err != nil {
		t.Fatal(err)
	}
	group, err := outboundgroup.NewFallback(
		outboundgroup.GroupCommonOption{Name: "user-route", URL: "https://probe.invalid"},
		outboundgroup.FallbackOption{Mode: "ordered"},
		nil, []P.ProxyProvider{pd},
	)
	if err != nil {
		t.Fatal(err)
	}
	assertSelected := func(want string) {
		t.Helper()
		if got := group.Now(); got != want {
			t.Fatalf("selected %q, want %q", got, want)
		}
	}
	assertSelected("primary")
	primary.alive = false
	assertSelected("backup")
	primary.alive = true
	assertSelected("primary")
	group.ForceSet("backup")
	assertSelected("backup")
	group.ForceSet("")
	assertSelected("primary")
}
