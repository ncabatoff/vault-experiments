package main

import (
	"fmt"
	consulapi "github.com/hashicorp/consul/api"
	vaultapi "github.com/hashicorp/vault/api"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"log"
	"net/http"
	"time"
)

var (
	vaults = prometheus.NewGauge(prometheus.GaugeOpts{Name: "client_vaults"})
	rpcs   = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "client_rpcs_total"},
		[]string{"vault_addr", "consul_node"})
	rpcerrs = prometheus.NewCounterVec(prometheus.CounterOpts{Name: "client_rpc_errors_total"},
		[]string{"vault_addr", "consul_node"})
)

func init() {
	http.Handle("/metrics", promhttp.Handler())
	prometheus.MustRegister(vaults)
	prometheus.MustRegister(rpcs)
	prometheus.MustRegister(rpcerrs)
	go http.ListenAndServe(":8080", nil)
}

func main() {
	consul, err := consulapi.NewClient(consulapi.DefaultConfig())
	if err != nil {
		log.Fatal(err)
	}
	health := consul.Health()

	for {
		csvc, _, _ := health.Service("vault", "", true, nil)
		vaults.Set(float64(len(csvc)))
		if len(csvc) == 0 {
			time.Sleep(time.Second)
			continue
		}

		// log.Printf("%# v, %# v", csvc[0].Node, csvc[0].Service)

		vaultcfg := vaultapi.DefaultConfig()
		vaultcfg.Address = fmt.Sprintf("http://%s:%d",
			csvc[0].Node.Address, csvc[0].Service.Port)
		vault, err := vaultapi.NewClient(vaultcfg)
		if err != nil {
			log.Fatal(err)
		}

		_, err = vault.Logical().Write("kv/data/foo", map[string]interface{}{
			"data": map[string]interface{}{
				"bar": "v1",
			},
		})
		if err != nil {
			log.Printf("error writing kv: %v", err)
			rpcerrs.WithLabelValues(vaultcfg.Address, csvc[0].Node.Node).Inc()
		}
		rpcs.WithLabelValues(vaultcfg.Address, csvc[0].Node.Node).Inc()
		time.Sleep(100 * time.Millisecond)
	}
}
