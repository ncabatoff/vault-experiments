package main

import (
	"github.com/hashicorp/vault/api"
	"log"
)

func main() {
	client, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		log.Fatal(err)
	}

	for {
		_, err := client.Logical().Write("/auth/token/renew-self", nil)
		if err != nil {
			log.Fatal(err)
		}
	}
}
