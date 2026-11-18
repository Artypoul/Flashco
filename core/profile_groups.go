package core

import "github.com/Artypoul/Flashco/modules/flashco_core"

type profileGroupReference = flashco_core.ProfileGroupReference
type profileGroupReferences = flashco_core.ProfileGroupReferences

func handleGetProfileGroupReferences(path string) ([]profileGroupReferences, error) {
	raw, err := handleReadConfig(PathParams{Path: path})
	if err != nil {
		return nil, err
	}
	return flashco_core.GetProfileGroupReferences(raw.ProxyGroup, len(raw.ProxyProvider))
}
