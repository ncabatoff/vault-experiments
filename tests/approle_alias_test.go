package tests

import (
	"github.com/hashicorp/vault/api"
	"github.com/ory/dockertest"
	"reflect"
	"strings"
	"testing"
	"time"
)

func prepareVaultContainer(t *testing.T) (cleanup func(), retURL string) {
	pool, err := dockertest.NewPool("")
	if err != nil {
		t.Fatalf("Failed to connect to docker: %s", err)
	}

	resource, err := pool.RunWithOptions(&dockertest.RunOptions{
		Repository:   "vault",
		Tag:          "1.0.0",
		CapAdd:       []string{"IPC_LOCK"},
		Env:          []string{"VAULT_DEV_ROOT_TOKEN_ID=devroot"},
		ExposedPorts: []string{"8200"},
	})
	if err != nil {
		t.Fatalf("Could not start local Vault docker container: %s", err)
	}

	cleanup = func() {
		cleanupResource(t, pool, resource)
	}

	retURL = "http://127.0.0.1:" + resource.GetPort("8200/tcp")

	// exponential backoff-retry
	if err = pool.Retry(func() error {
		return checkVault(t, retURL)
	}); err != nil {
		cleanup()
		t.Fatalf("Could not connect to Vault docker container: %s", err)
	}

	return
}

func getClient(t *testing.T, vaultAddr, token string) *api.Client {
	t.Helper()
	client, err := api.NewClient(api.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	_ = client.SetAddress(vaultAddr)
	client.SetToken(token)

	return client
}

func checkVault(t *testing.T, vaultAddr string) error {
	t.Helper()
	client := getClient(t, vaultAddr, "devroot")

	_, err := client.Logical().Read("/sys/mounts")
	return err
}

func cleanupResource(t *testing.T, pool *dockertest.Pool, resource *dockertest.Resource) {
	var err error
	for i := 0; i < 10; i++ {
		err = pool.Purge(resource)
		if err == nil {
			return
		}
		time.Sleep(1 * time.Second)
	}

	if strings.Contains(err.Error(), "No such container") {
		return
	}
	t.Fatalf("Failed to cleanup local container: %s", err)
}

func TestApprole(t *testing.T) {
	cleanup, vaultAddr := prepareVaultContainer(t)
	defer cleanup()

	client := getClient(t, vaultAddr, "devroot")
	err := client.Sys().PutPolicy("read", `
path "secret/test" {
   capabilities = ["read"]
}
`)
	if err != nil {
		t.Fatal(err)
	}

	err = client.Sys().PutPolicy("write", `
path "secret/test" {
   capabilities = ["create", "update"]
}
`)
	if err != nil {
		t.Fatal(err)
	}

	err = client.Sys().EnableAuth("approle", "approle", "desc")
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Logical().Write("auth/approle/role/myrole", map[string]interface{}{
		"policies": []string{"read"},
	})
	if err != nil {
		t.Fatal(err)
	}

	entity, err := client.Logical().Write("identity/entity", map[string]interface{}{
		"name":     "myentity",
		"policies": []string{"write"},
	})
	if err != nil {
		t.Fatal(err)
	}
	entityID := entity.Data["id"].(string)

	auths, err := client.Sys().ListAuth()
	if err != nil {
		t.Fatal(err)
	}

	roleID, err := client.Logical().Read("/auth/approle/role/myrole/role-id")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("%+v", roleID)
	_, err = client.Logical().Write("identity/entity-alias", map[string]interface{}{
		"name":           roleID.Data["role_id"],
		"canonical_id":   entityID,
		"mount_accessor": auths["approle/"].Accessor,
	})
	if err != nil {
		t.Fatal(err)
	}
	secretID, err := client.Logical().Write("/auth/approle/role/myrole/secret-id", nil)
	if err != nil {
		t.Fatal(err)
	}

	appClient, _ := api.NewClient(api.DefaultConfig())
	_ = appClient.SetAddress(vaultAddr)
	login, err := appClient.Logical().Write("auth/approle/login", map[string]interface{}{
		"role_id":   roleID.Data["role_id"],
		"secret_id": secretID.Data["secret_id"],
	})
	if err != nil {
		t.Fatal(err)
	}
	appClient.SetToken(login.Auth.ClientToken)
	_, err = client.Logical().Read("/sys/mounts")
	if err != nil {
		t.Fatal(err)
	}

	if !reflect.DeepEqual(login.Auth.Policies, []string{"default", "read", "write"}) {
		t.Fatalf("expected default+read+write, got: %v (%v)", login.Auth.Policies, login.Auth.IdentityPolicies)
	}
}
