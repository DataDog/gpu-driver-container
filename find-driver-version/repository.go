package main

import (
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
)

var packageNameRegex = regexp.MustCompile(`^Package:\s+(.+)\n`)
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
	_, err = io.Copy(&b, reader)
	if err != nil {
		return nil, err
	}

	return &Repository{
		sections: strings.Split(b.String(), "\n\n"),
	}, nil
}

func (r *Repository) GetMatchesOnPackages(regex *regexp.Regexp) []string {
	matches := []string{}
	for _, section := range r.sections {
		packageNameMatch := packageNameRegex.FindStringSubmatch(section)
		if len(packageNameMatch) >= 2 {
			match := regex.FindStringSubmatch(packageNameMatch[1])
			if len(match) >= 2 {
				matches = append(matches, match[1])
			}
		}
	}
	return matches
}

func (r *Repository) GetPackage(name string) *Package {
	packageSection := ""
	for _, section := range r.sections {
		if strings.Contains(section, fmt.Sprintf("Package: %s\n", name)) {
			packageSection = section
		}
	}
	if packageSection == "" {
		return nil
	}

	pkg := Package{
		Name: name,
	}

	lines := strings.Split(packageSection, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "Version: ") {
			pkg.Version = strings.TrimSpace(strings.TrimPrefix(line, "Version: "))
		}
		if strings.HasPrefix(line, "Depends: ") {
			packageDependency := strings.TrimSpace(strings.TrimPrefix(line, "Depends: "))
			dependencyMatch := nvidiaDriverDependencyRegex.FindStringSubmatch(packageDependency)
			if len(dependencyMatch) >= 2 {
				pkg.DependsOnDriverVersion = &dependencyMatch[1]
			}
		}
	}

	return &pkg
}
