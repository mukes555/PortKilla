#pragma once

// Exposes Darwin's libproc + proc_info interfaces to Swift so the scanner can
// enumerate processes and sockets with raw syscalls instead of spawning
// lsof/ps subprocesses.

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <pwd.h>
#include <unistd.h>
