package main

import (
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
)

var nvidiaDriverDependencyRegex = regexp.MustCompile(`nvidia-kernel-common-\d+-server\s*\(..\s*([\d\.]+)`)

type Repository struct {
	sections []string
}

type Package struct {
	Name                   string
	Version                string
	DependsOnDriverVersion *string
}

func GetRepository(url string, repository string) (*Repository, error) {
	repositoryUrl := fmt.Sprintf("https://%s/ubuntu/dists/%s/binary-amd64/Packages.gz", url, repository)

	resp, err := http.Get(repositoryUrl)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	reader, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, err
	}
	defer reader.Close()

	var b strings.Builder
	if _, err = io.Copy(&b, reader); err != nil {
		return nil, err
	}

	return &Repository{
		sections: strings.Split(b.String(), "\n\n"),
	}, nil
}

func (r *Repository) GetPackage(name string) *Package {
	for _, section := range r.sections {
		if !strings.Contains(section, fmt.Sprintf("Package: %s\n", name)) {
			continue
		}
		pkg := &Package{Name: name}
		for _, line := range strings.Split(section, "\n") {
			if strings.HasPrefix(line, "Version: ") {
				pkg.Version = strings.TrimSpace(strings.TrimPrefix(line, "Version: "))
			}
			if strings.HasPrefix(line, "Depends: ") {
				dep := strings.TrimSpace(strings.TrimPrefix(line, "Depends: "))
				if m := nvidiaDriverDependencyRegex.FindStringSubmatch(dep); len(m) >= 2 {
					pkg.DependsOnDriverVersion = &m[1]
				}
			}
		}
		return pkg
	}
	return nil
}
