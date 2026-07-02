package main

type MultiRepository struct {
	repositories []*Repository
}

type MultiPackage struct {
	packages []*Package
}

func GetMultiRepository(distro string) (*MultiRepository, error) {
	repos := []struct{ host, path string }{
		{"archive.ubuntu.com", distro + "/main"},
		{"archive.ubuntu.com", distro + "-updates/main"},
		{"archive.ubuntu.com", distro + "-security/main"},
		{"archive.ubuntu.com", distro + "-backports/main"},
		{"archive.ubuntu.com", distro + "/restricted"},
		{"archive.ubuntu.com", distro + "-updates/restricted"},
		{"archive.ubuntu.com", distro + "-security/restricted"},
		{"archive.ubuntu.com", distro + "-backports/restricted"},
		{"esm.ubuntu.com/fips-updates", distro + "-updates/main"},
	}

	mr := &MultiRepository{}
	for _, r := range repos {
		repo, err := GetRepository(r.host, r.path)
		if err != nil {
			return nil, err
		}
		mr.repositories = append(mr.repositories, repo)
	}
	return mr, nil
}

func (mr *MultiRepository) GetMultiPackage(name string) MultiPackage {
	mp := MultiPackage{}
	for _, r := range mr.repositories {
		if pkg := r.GetPackage(name); pkg != nil {
			mp.packages = append(mp.packages, pkg)
		}
	}
	return mp
}

func (mp *MultiPackage) GetVersions() []string {
	seen := make(map[string]bool)
	versions := []string{}
	for _, p := range mp.packages {
		if !seen[p.Version] {
			seen[p.Version] = true
			versions = append(versions, p.Version)
		}
	}
	return versions
}

func (mp *MultiPackage) GetNvidiaDriverDependencies() []string {
	seen := make(map[string]bool)
	deps := []string{}
	for _, p := range mp.packages {
		if p.DependsOnDriverVersion != nil && !seen[*p.DependsOnDriverVersion] {
			seen[*p.DependsOnDriverVersion] = true
			deps = append(deps, *p.DependsOnDriverVersion)
		}
	}
	return deps
}
