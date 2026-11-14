#pragma once
// sudoer grant / sudoer revoke: a passwordless sudo rule pinned to this binary's SHA-256.
#include <CommonCrypto/CommonDigest.h>
#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <iterator>
#include <mach-o/dyld.h>
#include <optional>
#include <pwd.h>
#include <spawn.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

extern char** environ;

namespace macos_input::sudoers {

inline constexpr const char* rule_path = "/private/etc/sudoers.d/macos-input";

inline std::string real_path(const std::string& path) {
    char resolved[PATH_MAX];
    if (!realpath(path.c_str(), resolved))
        return {};
    return resolved;
}

inline std::string executable_path() {
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::string path(size, '\0');
    if (_NSGetExecutablePath(path.data(), &size))
        throw std::runtime_error("Cannot locate the macos-input executable");
    path.resize(std::strlen(path.c_str()));
    auto resolved = real_path(path);
    if (resolved.empty())
        throw std::runtime_error("Cannot resolve the macos-input executable path");
    return resolved;
}

inline std::string sha256_hex(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file)
        throw std::runtime_error("Cannot read " + path);
    const std::string data{std::istreambuf_iterator<char>(file), {}};
    std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest{};
    CC_SHA256(data.data(), static_cast<CC_LONG>(data.size()), digest.data());
    std::string hex;
    for (const auto byte : digest) {
        char pair[3];
        std::snprintf(pair, sizeof pair, "%02x", byte);
        hex += pair;
    }
    return hex;
}

// sudoers needs escaping for spaces, commas, colons and more; refuse anything unusual instead.
inline bool sudoers_safe(const std::string& text, bool path) {
    return !text.empty() && text.front() != '-' &&
           std::all_of(text.begin(), text.end(), [&](char c) {
               return std::isalnum(static_cast<unsigned char>(c)) || c == '.' || c == '_' ||
                      c == '-' || c == '+' || (path && c == '/');
           });
}

// The resolved binary plus every PATH entry (e.g. Homebrew's bin symlink) that points at it.
inline std::vector<std::string> command_paths(const std::string& binary) {
    std::vector<std::string> paths{binary};
    std::string search = "/opt/homebrew/bin:/usr/local/bin";
    if (const char* env = std::getenv("PATH"))
        search += std::string(":") + env;
    std::istringstream dirs(search);
    for (std::string dir; std::getline(dirs, dir, ':');) {
        if (dir.empty() || dir.front() != '/')
            continue;
        const auto candidate = dir + "/macos-input";
        if (real_path(candidate) == binary &&
            std::find(paths.begin(), paths.end(), candidate) == paths.end())
            paths.push_back(candidate);
    }
    return paths;
}

inline std::string target_user(const std::optional<std::string>& requested) {
    std::string user;
    if (requested) {
        user = *requested;
    } else if (const char* sudo_user = std::getenv("SUDO_USER"); sudo_user && *sudo_user) {
        user = sudo_user;
    } else if (geteuid() != 0) {
        if (const auto* entry = getpwuid(getuid()))
            user = entry->pw_name;
    }
    if (user.empty())
        throw std::runtime_error("Cannot tell which user to grant; pass --user NAME");
    if (!sudoers_safe(user, false))
        throw std::runtime_error("Unsupported user name: " + user);
    const auto* entry = getpwnam(user.c_str());
    if (!entry)
        throw std::runtime_error("No such user: " + user);
    if (entry->pw_uid == 0)
        throw std::runtime_error("root does not need a sudo rule");
    return user;
}

inline std::string make_rule(const std::string& user) {
    const auto binary = executable_path();
    const auto digest = sha256_hex(binary);
    std::string commands;
    for (const auto& path : command_paths(binary)) {
        if (!sudoers_safe(path, true))
            throw std::runtime_error("Unsupported characters in executable path: " + path);
        commands += (commands.empty() ? "" : ", ") + std::string("sha256:") + digest + " " + path;
    }
    return "# Managed by `macos-input sudoer grant`; remove with `sudo macos-input sudoer revoke`.\n"
           "# Pinned to this build's SHA-256: after upgrading macos-input, sudo asks for a\n"
           "# password again until you rerun `sudo macos-input sudoer grant`.\n" +
           user + " ALL=(root) NOPASSWD: " + commands + "\n";
}

inline void require_root(const char* command) {
    if (geteuid() != 0)
        throw std::runtime_error(std::string("Run with sudo: sudo macos-input ") + command);
}

inline bool includes_sudoers_d() {
    std::ifstream file("/private/etc/sudoers");
    for (std::string line; std::getline(file, line);) {
        if ((line.starts_with("#includedir ") || line.starts_with("@includedir ")) &&
            (line.ends_with(" /private/etc/sudoers.d") || line.ends_with(" /etc/sudoers.d")))
            return true;
    }
    return false;
}

inline int visudo_check(const std::string& path) {
    const char* argv[] = {"/usr/sbin/visudo", "-c", "-q", "-f", path.c_str(), nullptr};
    pid_t pid = 0;
    if (posix_spawn(&pid, argv[0], nullptr, nullptr, const_cast<char**>(argv), environ))
        throw std::runtime_error("Cannot run visudo");
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

inline int grant(const std::optional<std::string>& requested_user, bool dry_run) {
    const auto rule = make_rule(target_user(requested_user));
    if (dry_run) {
        std::cout << rule;
        return 0;
    }
    require_root("sudoer grant");
    if (!includes_sudoers_d())
        throw std::runtime_error("/etc/sudoers does not include /private/etc/sudoers.d");
    // sudo skips include files whose names contain a dot, so the temp file is never live.
    std::string temp = std::string(rule_path) + ".XXXXXX";
    const int fd = mkstemp(temp.data());
    if (fd < 0)
        throw std::runtime_error("Cannot create a file in /private/etc/sudoers.d");
    const bool written = fchown(fd, 0, 0) == 0 && fchmod(fd, 0440) == 0 &&
                         write(fd, rule.data(), rule.size()) == static_cast<ssize_t>(rule.size());
    close(fd);
    if (!written || visudo_check(temp) != 0 || rename(temp.c_str(), rule_path) != 0) {
        unlink(temp.c_str());
        throw std::runtime_error("Could not install a valid sudoers rule; nothing was changed");
    }
    std::cout << "Wrote " << rule_path << ":\n" << rule;
    return 0;
}

inline int revoke(bool dry_run) {
    if (dry_run) {
        std::cout << "would remove " << rule_path << '\n';
        return 0;
    }
    require_root("sudoer revoke");
    if (unlink(rule_path) != 0) {
        if (errno != ENOENT)
            throw std::runtime_error(std::string("Cannot remove ") + rule_path);
        std::cout << "No rule at " << rule_path << '\n';
        return 0;
    }
    std::cout << "Removed " << rule_path << '\n';
    return 0;
}

} // namespace macos_input::sudoers
