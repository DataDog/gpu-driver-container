package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"rsc.io/getopt"
)

var (
	driverBranch   = flag.String("driver-branch", "", "target branch of the nvidia driver (example: `570`)")
	kernelVersion  = flag.String("kernel-version", "", "version of the kernel (example: `6.8.0-1032-aws`)")
	ubuntuDistro   = flag.String("ubuntu-distro", "", "ubuntu distribution codename (example: `noble`)")
)

func main() {
	getopt.Alias("d", "driver-branch")
	getopt.Alias("k", "kernel-version")
	getopt.Alias("u", "ubuntu-distro")

	getopt.CommandLine.Usage = func() {
		fmt.Fprintf(os.Stderr, "usage: %s -d <driver-branch> -k <kernel-version> -u <ubuntu-distro>\n", os.Args[0])
		getopt.PrintDefaults()
	}
	getopt.Parse()

	if *driverBranch == "" || *kernelVersion == "" || *ubuntuDistro == "" {
		getopt.CommandLine.Usage()
		os.Exit(1)
	}

	multiRepository, err := GetMultiRepository(*ubuntuDistro)
	if err != nil {
		fmt.Fprintf(os.Stderr, "could not fetch nvidia repositories: %v\n", err)
		os.Exit(1)
	}

	// Get the driver version dependency from the kernel module package
	linuxModuleNvidiaPackageName := fmt.Sprintf("linux-modules-nvidia-%s-server-open-%s", *driverBranch, *kernelVersion)
	linuxModuleNvidiaMultiPackage := multiRepository.GetMultiPackage(linuxModuleNvidiaPackageName)
	nvidiaDriverDependencies := linuxModuleNvidiaMultiPackage.GetNvidiaDriverDependencies()

	if len(nvidiaDriverDependencies) == 0 {
		fmt.Fprintf(os.Stderr, "package %s not found or has no driver dependency\n", linuxModuleNvidiaPackageName)
		os.Exit(1)
	}

	targetDriverVersion := nvidiaDriverDependencies[0]

	// Find the full versioned package matching the dependency
	nvidiaDriverMultiPackage := multiRepository.GetMultiPackage(fmt.Sprintf("nvidia-driver-%s-server-open", *driverBranch))
	for _, version := range nvidiaDriverMultiPackage.GetVersions() {
		if strings.Split(version, "-")[0] == targetDriverVersion {
			fmt.Println(version)
			return
		}
	}

	fmt.Fprintf(os.Stderr, "no available driver version matching %s\n", targetDriverVersion)
	os.Exit(1)
}
