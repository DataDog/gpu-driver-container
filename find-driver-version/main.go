package main

import (
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"

	"rsc.io/getopt"
)

var (
	driverBranch        = flag.String("driver-branch", "", "target branch of the nvidia driver (example: `570`)")
	kernelVersion       = flag.String("kernel-version", "", "version of the kernel (example `6.8.0-1032-aws`, if not specified all available versions are considered)")
	kernelSemver        = flag.String("kernel-semver", "", "semver for the kernel version (example `6.8.0`, only applied if the kernel version is not set, if not specified all available semver are considered)")
	kernelCloudProvider = flag.String("kernel-cloud-provider", "aws,gcp,azure", "comma-separated list of cloud providers for the kernel version (example `aws,gcp`, only applied if the kernel version is not set)")
	help                = flag.Bool("help", false, "display this help message")
)

func printUsage() {
	fmt.Fprintf(os.Stderr, "usage: %s -d <driver major>\n", os.Args[0])
	fmt.Fprintf(os.Stderr, "       %s -d <driver major> -k <kernel semver>-<kernel patch>-<cloud-provider>\n", os.Args[0])
	getopt.PrintDefaults()
}

func main() {
	getopt.Alias("d", "driver-branch")
	getopt.Alias("k", "kernel-version")
	getopt.Alias("s", "kernel-semver")
	getopt.Alias("c", "kernel-cloud-provider")
	getopt.Alias("h", "help")

	getopt.CommandLine.Usage = func() {}
	getopt.Parse()

	var err error
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: could not initialize logger: %q\n", err)
		os.Exit(1)
	}

	if len(flag.Args()) != 0 {
		fmt.Fprintf(os.Stderr, "no positional argument is expected\n")
		printUsage()
		os.Exit(1)
	}

	if *help {
		printUsage()
		os.Exit(0)
	}

	if *driverBranch == "" {
		fmt.Fprintf(os.Stderr, "driver branch was not specified\n")
		printUsage()
		os.Exit(1)
	}

	multiRepository, err := GetMultiRepository()
	if err != nil {
		fmt.Fprintf(os.Stderr, "could not fetch nvidia repositories: %v", err)
		os.Exit(1)
	}

	// Create the list of kernel versions to find drivers
	kernelVersions := []string{}
	if *kernelVersion != "" {
		linuxModuleNvidiaPackageRegex := regexp.MustCompile(fmt.Sprintf("linux-modules-nvidia-%s-server-open-(%s)", *driverBranch, regexp.QuoteMeta(*kernelVersion)))
		kernelVersions = multiRepository.GetMatchesOnPackages(linuxModuleNvidiaPackageRegex)
		if len(kernelVersions) == 0 {
			fmt.Fprintf(os.Stderr, "[error] kernel version %s not available\n", *kernelVersion)
			os.Exit(1)
		}
	} else {
		// Get kernel regex
		kernelRegexSemver := `\d+\.\d+\.\d+`
		if *kernelSemver != "" {
			kernelRegexSemver = regexp.QuoteMeta(*kernelSemver)
		}
		kernelRegexCloudProvider := strings.Join(strings.Split(*kernelCloudProvider, ","), ")|(?:")
		kernelRegex := fmt.Sprintf("%s-(?:\\d)+-(?:(?:%s))", kernelRegexSemver, kernelRegexCloudProvider)

		linuxModuleNvidiaPackageRegex := regexp.MustCompile(fmt.Sprintf("^linux-modules-nvidia-%s-server-open-(%s)$", *driverBranch, kernelRegex))
		kernelVersions = multiRepository.GetMatchesOnPackages(linuxModuleNvidiaPackageRegex)
		fmt.Fprintf(os.Stderr, "[info] found following available kernel versions: %v\n", kernelVersions)
	}

	// Exclude kernels that are in the exclusion list
	availableKernelVersions, excludedKernels := SeparateExcludedKernels(*driverBranch, kernelVersions)
	if len(excludedKernels) != 0 {
		fmt.Fprintf(os.Stderr, "[warn] following kernel versions were excluded as they are in the exclusion list: %v\n", excludedKernels)
	}

	// Get the list of available driver versions
	nvidiaDriverMultiPackage := multiRepository.GetMultiPackage(fmt.Sprintf("nvidia-driver-%s-server-open", *driverBranch))
	availableNvidiaDriverVersions := nvidiaDriverMultiPackage.GetVersions()
	fmt.Fprintf(os.Stderr, "[info] found following available driver versions: %v\n", availableNvidiaDriverVersions)
	if len(availableNvidiaDriverVersions) == 0 {
		fmt.Fprintf(os.Stderr, "no available nvidia driver version")
		os.Exit(1)
	}

	// Find the appropriate driver for all kernel versions
	appropriateDriverForKernel := map[string]string{}
	for _, version := range availableKernelVersions {
		linuxModuleNvidiaPackageName := fmt.Sprintf("linux-modules-nvidia-%s-server-open-%s", *driverBranch, version)
		linuxModuleNvidiaMultiPackage := multiRepository.GetMultiPackage(linuxModuleNvidiaPackageName)
		nvidiaDriverDependencies := linuxModuleNvidiaMultiPackage.GetNvidiaDriverDependencies()

		// Get the eventual driver version dependency for the linux-modules-nvidia-*-server-open-* package
		targetDriverVersion := ""
		for _, dependency := range nvidiaDriverDependencies {
			if targetDriverVersion == "" {
				targetDriverVersion = dependency
			} else if targetDriverVersion != dependency {
				fmt.Fprintf(os.Stderr, "[warn] found multiple driver version dependencies for package %s, selecting %s\n", linuxModuleNvidiaPackageName, targetDriverVersion)
			}
		}

		if targetDriverVersion == "" {
			fmt.Fprintf(os.Stderr, "[info] no driver version dependencies for package %s, selecting %s\n", linuxModuleNvidiaPackageName, availableNvidiaDriverVersions[0])
			appropriateDriverForKernel[version] = availableNvidiaDriverVersions[0]
		} else {
			// For all available driver versions, check if it matches the dependency
			matchingNvidiaDriverVersions := []string{}
			for _, availableNvidiaDriverVersion := range availableNvidiaDriverVersions {
				if strings.Split(availableNvidiaDriverVersion, "-")[0] == targetDriverVersion {
					matchingNvidiaDriverVersions = append(matchingNvidiaDriverVersions, availableNvidiaDriverVersion)
				}
			}

			if len(matchingNvidiaDriverVersions) == 0 {
				fmt.Fprintf(os.Stderr, "[warn] no available driver version matching %s found for package %s, skipping kernel %s\n", targetDriverVersion, linuxModuleNvidiaPackageName, version)
			} else {
				if len(matchingNvidiaDriverVersions) > 1 {
					fmt.Fprintf(os.Stderr, "[info] multiple driver versions matching %s found for package %s, selecting %s\n", targetDriverVersion, linuxModuleNvidiaPackageName, matchingNvidiaDriverVersions[0])
				}
				appropriateDriverForKernel[version] = matchingNvidiaDriverVersions[0]
			}
		}
	}

	for kernel, driver := range appropriateDriverForKernel {
		fmt.Printf("%s -> %s\n", kernel, driver)
	}
}
