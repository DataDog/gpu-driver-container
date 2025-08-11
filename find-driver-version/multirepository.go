package main

import "regexp"

var NvidiaRepositories = []string{
	"jammy/restricted",
	"jammy-updates/restricted",
	"jammy-security/restricted",
	"jammy-backports/restricted",
}

type MultiRepository struct {
	repositories []*Repository
}

type MultiPackage struct {
	packages []*Package
}

func GetMultiRepository() (*MultiRepository, error) {
	multiRepository := MultiRepository{}
	for _, repositoryName := range NvidiaRepositories {
		repository, err := GetRepository(repositoryName)
		if err != nil {
			return nil, err
		}
		multiRepository.repositories = append(multiRepository.repositories, repository)
	}
	return &multiRepository, nil
}

func (mr *MultiRepository) GetMatchesOnPackages(regex *regexp.Regexp) []string {
	matchExists := make(map[string]bool)
	matches := []string{}

	for _, r := range mr.repositories {
		for _, match := range r.GetMatchesOnPackages(regex) {
			if !matchExists[match] {
				matchExists[match] = true
				matches = append(matches, match)
			}
		}
	}

	return matches
}

func (mr *MultiRepository) GetMultiPackage(name string) MultiPackage {
	multiPackage := MultiPackage{}

	for _, r := range mr.repositories {
		pkg := r.GetPackage(name)
		if pkg != nil {
			multiPackage.packages = append(multiPackage.packages, pkg)
		}
	}

	return multiPackage
}

func (mp *MultiPackage) GetVersions() []string {
	versionExists := make(map[string]bool)
	versions := []string{}

	for _, p := range mp.packages {
		if !versionExists[p.Version] {
			versionExists[p.Version] = true
			versions = append(versions, p.Version)
		}
	}

	return versions
}

func (mp *MultiPackage) GetNvidiaDriverDependencies() []string {
	dependencyExists := make(map[string]bool)
	dependencies := []string{}

	for _, p := range mp.packages {
		if p.DependsOnDriverVersion != nil && !dependencyExists[*p.DependsOnDriverVersion] {
			dependencyExists[*p.DependsOnDriverVersion] = true
			dependencies = append(dependencies, *p.DependsOnDriverVersion)
		}
	}

	return dependencies
}
