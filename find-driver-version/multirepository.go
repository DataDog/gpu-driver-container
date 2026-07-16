package main

const aptMirror = "us-east-1.ec2.archive.ubuntu.com"

type MultiRepository struct {
	repositories []*Repository
}

type MultiPackage struct {
	packages []*Package
}

func GetMultiRepository(distro string) (*MultiRepository, error) {
	repos := []struct{ host, path string }{
		{aptMirror, distro + "/main"},
		{aptMirror, distro + "-updates/main"},
		{aptMirror, distro + "-security/main"},
		{aptMirror, distro + "-backports/main"},
		{aptMirror, distro + "/restricted"},
		{aptMirror, distro + "-updates/restricted"},
		{aptMirror, distro + "-security/restricted"},
		{aptMirror, distro + "-backports/restricted"},
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
