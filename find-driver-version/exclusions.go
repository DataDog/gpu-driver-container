package main

// Maintain a list of kernels that cannot be downloaded and should not be considered for specific driver branches
var driverTagExclusions = map[string][]string{
	"550": []string{
		// only available version for linux-modules-nvidia-550-server-6.8.0-1031-azure is 6.8.0-1031.36~22.04.1
		// it depends on linux-signatures-nvidia-6.8.0-1031-azure=6.8.0-1031.36~22.04.1 which is not available
		"6.8.0-1031-azure",
	},
}

func SeparateExcludedKernels(driverBranch string, kernels []string) ([]string, []string) {
	validKernels := []string{}
	excludedKernels := []string{}

	exclusions, _ := driverTagExclusions[driverBranch]

	for _, k := range kernels {
		isExcluded := false
		for _, e := range exclusions {
			if k == e {
				excludedKernels = append(excludedKernels, k)
				isExcluded = true
			}
		}
		if !isExcluded {
			validKernels = append(validKernels, k)
		}
	}

	return validKernels, excludedKernels
}
