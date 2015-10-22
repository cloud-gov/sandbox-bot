package main

type Settings struct {
	ClientID     string `envconfig:"client_id"`
	ClientSecret string `envconfig:"client_secret"`
	UaaURL       string `envconfig:"uaa_url"`
	Domains      string `envconfig:"domains"`
}

type CFApiResult struct {
	NextURL   interface{} `json:"next_url"`
	PrevURL   interface{} `json:"prev_url"`
	Resources []struct {
		Entity struct {
			Active                         bool   `json:"active"`
			Admin                          bool   `json:"admin"`
			AuditedOrganizationsURL        string `json:"audited_organizations_url"`
			AuditedSpacesURL               string `json:"audited_spaces_url"`
			BillingManagedOrganizationsURL string `json:"billing_managed_organizations_url"`
			DefaultSpaceGUID               string `json:"default_space_guid"`
			DefaultSpaceURL                string `json:"default_space_url"`
			ManagedOrganizationsURL        string `json:"managed_organizations_url"`
			ManagedSpacesURL               string `json:"managed_spaces_url"`
			OrganizationsURL               string `json:"organizations_url"`
			SpacesURL                      string `json:"spaces_url"`
			Username                       string `json:"username"`
		} `json:"entity"`
		Metadata struct {
			CreatedAt string      `json:"created_at"`
			GUID      string      `json:"guid"`
			UpdatedAt interface{} `json:"updated_at"`
			URL       string      `json:"url"`
		} `json:"metadata"`
	} `json:"resources"`
	TotalPages   int `json:"total_pages"`
	TotalResults int `json:"total_results"`
}

type DomainMap struct {
	Domain string
	Space  string
	GUID   string
	Spaces []Space
}

type SpacesAPIResult struct {
	NextURL      interface{} `json:"next_url"`
	PrevURL      interface{} `json:"prev_url"`
	Spaces       []Space     `json:"resources"`
	TotalPages   int         `json:"total_pages"`
	TotalResults int         `json:"total_results"`
}

type Space struct {
	Entity struct {
		AllowSSH                 bool        `json:"allow_ssh"`
		AppEventsURL             string      `json:"app_events_url"`
		AppsURL                  string      `json:"apps_url"`
		AuditorsURL              string      `json:"auditors_url"`
		DevelopersURL            string      `json:"developers_url"`
		DomainsURL               string      `json:"domains_url"`
		EventsURL                string      `json:"events_url"`
		ManagersURL              string      `json:"managers_url"`
		Name                     string      `json:"name"`
		OrganizationGUID         string      `json:"organization_guid"`
		OrganizationURL          string      `json:"organization_url"`
		RoutesURL                string      `json:"routes_url"`
		SecurityGroupsURL        string      `json:"security_groups_url"`
		ServiceInstancesURL      string      `json:"service_instances_url"`
		SpaceQuotaDefinitionGUID interface{} `json:"space_quota_definition_guid"`
	} `json:"entity"`
	Metadata struct {
		CreatedAt string      `json:"created_at"`
		GUID      string      `json:"guid"`
		UpdatedAt interface{} `json:"updated_at"`
		URL       string      `json:"url"`
	} `json:"metadata"`
}

type CreateSpaceAPI struct {
	Name             string   `json:"name"`
	OrganizationGUID string   `json:"organization_guid"`
	DeveloperGUIDs   []string `json:"developer_guids"`
	ManagerGUIDs     []string `json:"manager_guids"`
}
