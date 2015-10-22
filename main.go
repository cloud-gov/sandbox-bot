package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"strings"

	"github.com/kelseyhightower/envconfig"
	// "golang.org/x/oauth2"
	"golang.org/x/net/context"
	"golang.org/x/oauth2/clientcredentials"
)

func getAndUnmarshal(client *http.Client, url string, output interface{}) error {
	res, err := client.Get(url)
	if err != nil {
		return err
	}

	body, err := ioutil.ReadAll(res.Body)
	if err != nil {
		return err
	}

	// Parse JSON
	err = json.Unmarshal(body, &output)
	if err != nil {
		fmt.Printf("%T\n%s\n%#v\n", err, err, err)
		switch v := err.(type) {
		case *json.SyntaxError:
			fmt.Println(string(body[v.Offset-40 : v.Offset]))
		}
		return err
	}

	return nil
}

func main() {
	// Build up settings
	var s Settings
	envconfig.Process("", &s)

	var dm []DomainMap
	err := json.Unmarshal([]byte(s.Domains), &dm)
	if err != nil {
		panic(err)
	}

	conf := &clientcredentials.Config{
		ClientID:     s.ClientID,
		ClientSecret: s.ClientSecret,
		Scopes:       []string{"cloud_controller.admin"},
		TokenURL:     s.UaaURL + "/oauth/token",
	}

	client := conf.Client(context.Background())

	// Get Spaces
	for k, domain := range dm {
		var s SpacesAPIResult

		err = getAndUnmarshal(client, "https://api.cloud.gov/v2/organizations/"+domain.GUID+"/spaces?results-per-page=100", &s)
		if err != nil {
			panic(err)
		}
		dm[k].Spaces = s.Spaces
	}

	// Get users
	var r CFApiResult
	err = getAndUnmarshal(client, "https://api.cloud.gov/v2/users?order-direction=desc", &r)
	if err != nil {
		panic(err)
	}

	// Do something with users

	for _, user := range r.Resources {
		if user.Entity.Username == "" ||
			!strings.Contains(user.Entity.Username, "@") {
			continue
		}
		email := strings.Split(user.Entity.Username, "@")

		var domainMatch *DomainMap
		domainMatch = nil
		for i, domain := range dm {
			if domain.Domain == email[1] {
				// Found a domain mapping
				domainMatch = &dm[i]
			}
		}

		if domainMatch == nil {
			continue
		}
		fmt.Println(user.Entity.Username)

		found := false
		for _, space := range domainMatch.Spaces {
			if email[0] == space.Entity.Name {
				found = true
			}
		}
		if found {
			fmt.Println("Found Space")
		} else {
			var newSpaceReq CreateSpaceAPI
			newSpaceReq.Name = email[0]
			newSpaceReq.OrganizationGUID = domainMatch.GUID
			newSpaceReq.DeveloperGUIDs = append(newSpaceReq.DeveloperGUIDs, user.Metadata.GUID)
			newSpaceReq.ManagerGUIDs = append(newSpaceReq.ManagerGUIDs, user.Metadata.GUID)

			r, _ := json.Marshal(newSpaceReq)

			fmt.Println(string(r))
			res, _ := client.Post("https://api.cloud.gov/v2/spaces",
				"application/json",
				bytes.NewBuffer(r))

			body, _ := ioutil.ReadAll(res.Body)
			fmt.Println(string(body))

		}

	}
}
