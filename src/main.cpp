#include "driver_setup.hpp"
#include "mouse.hpp"
#include <CoreGraphics/CoreGraphics.h>
#include <chrono>
#include <condition_variable>
#include <csignal>
#include <iostream>
#include <map>
#include <mutex>
#include <optional>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <pqrs/osx/autorelease_pool.hpp>
#include <sstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

using namespace std::chrono_literals;
namespace hid = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;
namespace service = pqrs::karabiner::driverkit::virtual_hid_device_service;

namespace {
using namespace macos_input;
volatile std::sig_atomic_t interrupted = 0;

hid::keyboard_input parse_chord(const std::string& chord) {
    const std::map<std::string, hid::modifier> modifiers{{"cmd", hid::modifier::left_command},
                                                         {"ctrl", hid::modifier::left_control},
                                                         {"shift", hid::modifier::left_shift},
                                                         {"alt", hid::modifier::left_option},
                                                         {"option", hid::modifier::left_option}};
    const std::map<std::string, uint16_t> keys{
        {"enter", 0x28},     {"escape", 0x29},       {"backspace", 0x2a},
        {"tab", 0x2b},       {"space", 0x2c},        {"minus", 0x2d},
        {"equal", 0x2e},     {"left-bracket", 0x2f}, {"right-bracket", 0x30},
        {"backslash", 0x31}, {"semicolon", 0x33},    {"quote", 0x34},
        {"grave", 0x35},     {"comma", 0x36},        {"period", 0x37},
        {"slash", 0x38},     {"delete", 0x4c},       {"right", 0x4f},
        {"left", 0x50},      {"down", 0x51},         {"up", 0x52}};
    hid::keyboard_input report;
    alignas(uint16_t) hid::keys pressed_keys;
    bool has_key = false;
    size_t start = 0;
    for (;;) {
        const auto end = chord.find('+', start);
        const auto part = chord.substr(start, end == std::string::npos ? end : end - start);
        if (const auto modifier = modifiers.find(part); modifier != modifiers.end()) {
            report.modifiers.insert(modifier->second);
        } else {
            uint16_t code;
            if (part.size() == 1 && part[0] >= 'a' && part[0] <= 'z') {
                code = 0x04 + part[0] - 'a';
            } else if (part.size() == 1 && part[0] >= '1' && part[0] <= '9') {
                code = 0x1e + part[0] - '1';
            } else if (part == "0") {
                code = 0x27;
            } else if (const auto key = keys.find(part); key != keys.end()) {
                code = key->second;
            } else {
                throw std::runtime_error("Unknown or empty key in chord: " + chord);
            }
            if (has_key) {
                throw std::runtime_error("Use one key plus modifiers per chord: " + chord);
            }
            pressed_keys.insert(code);
            has_key = true;
        }
        if (end == std::string::npos)
            break;
        start = end + 1;
    }
    if (!has_key)
        throw std::runtime_error("Chord needs a non-modifier key: " + chord);
    // The packed report places its 16-bit keys at an unaligned byte offset.
    std::memcpy(&report.keys, &pressed_keys, sizeof(pressed_keys));
    return report;
}

struct Dispatcher {
    Dispatcher() {
        pqrs::dispatcher::extra::initialize_shared_dispatcher(
            pqrs::osx::autorelease_pool::execute_with_autorelease_pool);
    }
    ~Dispatcher() { pqrs::dispatcher::extra::terminate_shared_dispatcher(); }
};

class Device {
public:
    Device(bool keyboard, bool pointing) : keyboard_(keyboard), pointing_(pointing) {
        client_ = std::make_unique<service::client>();
        client_->connected.connect([this] {
            if (keyboard_) {
                // A country code lets macOS identify the keyboard type, as in upstream's example.
                service::virtual_hid_keyboard_parameters parameters;
                parameters.set_country_code(pqrs::hid::country_code::us);
                client_->async_virtual_hid_keyboard_initialize(parameters);
            }
            if (pointing_)
                client_->async_virtual_hid_pointing_initialize();
        });
        client_->virtual_hid_keyboard_ready.connect([this](bool ready) {
            std::lock_guard lock(mutex_);
            keyboard_ready_ = ready;
            changed_.notify_all();
        });
        client_->virtual_hid_pointing_ready.connect([this](bool ready) {
            std::lock_guard lock(mutex_);
            pointing_ready_ = ready;
            changed_.notify_all();
        });
        client_->connect_failed.connect([this](const auto& error) { fail(error.message()); });
        client_->error_occurred.connect([this](const auto& error) { fail(error.message()); });
        client_->warning_reported.connect([this](const auto& message) { fail(message); });
        client_->closed.connect([this] { fail("Driver daemon connection closed"); });
        client_->driver_version_mismatched.connect([this](bool mismatch) {
            if (mismatch)
                fail("Driver version mismatch; this client uses v8.8.0 headers");
        });
        client_->async_start();
    }

    // Reports are queued asynchronously; give the last ones time to reach the daemon.
    ~Device() { std::this_thread::sleep_for(100ms); }

    void wait_ready() {
        std::unique_lock lock(mutex_);
        if (!changed_.wait_for(lock, 10s, [this] { return ready() || !error_.empty(); })) {
            throw std::runtime_error("Virtual input not ready; check driver activation and daemon");
        }
        check_error();
    }

    void tap(const hid::keyboard_input& report) {
        send(report);
        std::this_thread::sleep_for(50ms);
        send(hid::keyboard_input{});
        std::this_thread::sleep_for(10ms);
    }

    void move(Delta delta) {
        hid::pointing_input report;
        report.x = static_cast<uint8_t>(delta.x);
        report.y = static_cast<uint8_t>(delta.y);
        send(report);
    }

private:
    void fail(const std::string& message) {
        std::lock_guard lock(mutex_);
        error_ = message;
        changed_.notify_all();
    }

    void check_error() const {
        if (!error_.empty())
            throw std::runtime_error(error_);
    }

    bool ready() const {
        return (!keyboard_ || keyboard_ready_) && (!pointing_ || pointing_ready_);
    }

    // The daemon doesn't acknowledge input reports, so posting is fire-and-forget.
    template <typename Report> void send(const Report& report) {
        std::lock_guard lock(mutex_);
        check_error();
        if (!ready())
            throw std::runtime_error("Virtual input disconnected");
        client_->async_post_report(report);
    }

    Dispatcher dispatcher_;
    std::mutex mutex_;
    std::condition_variable changed_;
    const bool keyboard_;
    const bool pointing_;
    bool keyboard_ready_ = false;
    bool pointing_ready_ = false;
    std::string error_;
    std::unique_ptr<service::client> client_;
};

struct Command {
    std::vector<std::string> chords;
    std::optional<Move> move;
};

Command parse_command(std::vector<std::string> args) {
    if (args.empty())
        throw std::runtime_error("Missing command; see --help");
    if (args.front() == "move")
        return {{}, parse_move(args)};
    if (args.front() == "key")
        args.erase(args.begin());
    if (args.empty())
        throw std::runtime_error("key needs a chord");
    for (const auto& chord : args)
        parse_chord(chord);
    return {std::move(args), std::nullopt};
}

macos_input::Point cursor_position() {
    const auto event = CGEventCreate(nullptr);
    if (!event)
        throw std::runtime_error("Cannot read cursor position");
    const auto point = CGEventGetLocation(event);
    CFRelease(event);
    return {point.x, point.y};
}

std::vector<Bounds> displays() {
    uint32_t count = 0;
    if (CGGetActiveDisplayList(0, nullptr, &count) != kCGErrorSuccess || count == 0)
        throw std::runtime_error("Cannot enumerate active displays");
    std::vector<CGDirectDisplayID> ids(count);
    if (CGGetActiveDisplayList(count, ids.data(), &count) != kCGErrorSuccess)
        throw std::runtime_error("Cannot read active displays");
    std::vector<Bounds> result;
    for (uint32_t i = 0; i < count; ++i) {
        const auto bounds = CGDisplayBounds(ids[i]);
        result.push_back({bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height});
    }
    return result;
}

void check_interrupted() {
    if (interrupted)
        throw std::runtime_error("Interrupted");
}

void relative_move(Device& device, int64_t x, int64_t y) {
    while (x || y) {
        check_interrupted();
        const auto step = relative_step(x, y);
        device.move(step);
        x -= step.x;
        y -= step.y;
    }
}

void move_pointer(Device& device, const Move& move) {
    const auto began = std::chrono::steady_clock::now();
    const auto elapsed = [&] {
        return std::chrono::duration<double>(std::chrono::steady_clock::now() - began).count();
    };
    if (move.coordinates == Coordinates::relative) {
        int64_t sent_x = 0, sent_y = 0;
        for (;;) {
            check_interrupted();
            const double fraction = progress(elapsed(), move.seconds);
            const auto x = std::llround(move.position.x * fraction);
            const auto y = std::llround(move.position.y * fraction);
            relative_move(device, x - sent_x, y - sent_y);
            sent_x = x;
            sent_y = y;
            if (fraction == 1)
                return;
            std::this_thread::sleep_for(10ms);
        }
    }

    const auto start = cursor_position();
    auto target = move.position;
    const auto screens = displays();
    if (move.coordinates == Coordinates::percent) {
        const auto screen = std::find_if(screens.begin(), screens.end(),
                                         [&](Bounds bounds) { return bounds.contains(start); });
        if (screen == screens.end())
            throw std::runtime_error("Cursor is not on an active display");
        target = percent_target(*screen, move.position);
    }
    if (std::none_of(screens.begin(), screens.end(),
                     [&](Bounds bounds) { return bounds.contains(target); }))
        throw std::runtime_error("Absolute target is outside the active displays");

    macos_input::Point gain{1, 1};
    for (;;) {
        check_interrupted();
        const auto current = cursor_position();
        const auto seconds = elapsed();
        const auto fraction = progress(seconds, move.seconds);
        if (fraction == 1 && reached(current, target))
            return;
        if (seconds - move.seconds > 5)
            throw std::runtime_error("Could not reach target within 0.5 screen points; cursor at " +
                                     std::to_string(current.x) + "," + std::to_string(current.y));
        const auto desired = interpolate(start, target, fraction);
        const Delta step{correction(desired.x - current.x, gain.x),
                         correction(desired.y - current.y, gain.y)};
        if (step.x || step.y)
            device.move(step);
        std::this_thread::sleep_for(10ms);
        const auto after = cursor_position();
        if (step.x && after.x != current.x)
            gain.x = std::clamp(std::abs((after.x - current.x) / step.x), 0.25, 16.0);
        if (step.y && after.y != current.y)
            gain.y = std::clamp(std::abs((after.y - current.y) / step.y), 0.25, 16.0);
    }
}
} // namespace

int main(int argc, char** argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--version") {
            std::cout << "macos-input " << MACOS_INPUT_VERSION << '\n';
            return 0;
        }
        bool dry_run = false;
        bool from_stdin = false;
        std::vector<std::string> args;
        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg == "--help" || arg == "-h") {
                std::cout
                    << "Usage: macos-input [--dry-run] key CHORD [CHORD ...]\n"
                       "       macos-input [--dry-run] move relative|absolute|percent X Y "
                       "[--smooth SECONDS]\n"
                       "       macos-input [--dry-run] --stdin\n"
                       "       macos-input --version\n"
                       "Keys: lowercase letters/digits, cmd/ctrl/shift/alt/option modifiers,\n"
                       "enter, escape, backspace, tab, space, punctuation names and arrow keys.\n"
                       "Relative: integer HID counts, affected by mouse acceleration.\n"
                       "Absolute: global screen points; percent: 0-100 on the cursor's display.\n"
                       "Default: no animation. --smooth SECONDS adds ease-in/out movement.\n"
                       "All input uses the driver. Absolute targets allow 0.5-point error and "
                       "fail\n"
                       "after 5 seconds of correction; no native cursor-warp fallback.\n"
                       "--stdin: persistent devices; prints ready, then ok per command line.\n"
                       "--dry-run: validates syntax only; no root, driver, screen reads or input.\n"
                       "Live input requires root, the virtual-hid-driver cask and its daemon.\n";
                return 0;
            } else if (arg == "--dry-run") {
                dry_run = true;
            } else if (arg == "--stdin") {
                from_stdin = true;
            } else {
                args.push_back(arg);
            }
        }
        if (from_stdin ? !args.empty() : args.empty()) {
            throw std::runtime_error("Supply a command or --stdin; see --help");
        }
        std::optional<Command> command;
        if (!from_stdin)
            command = parse_command(args);

        struct sigaction action{};
        action.sa_handler = [](int) { interrupted = 1; };
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGINT, &action, nullptr) || sigaction(SIGTERM, &action, nullptr)) {
            throw std::runtime_error("Cannot install signal handlers");
        }
        std::unique_ptr<Device> device;
        if (!dry_run) {
            struct stat status{};
            if (stat("/Applications/.Karabiner-VirtualHIDDevice-Manager.app", &status)) {
                std::cerr << "macos-input: virtual HID driver is not installed.\n\n"
                          << driver_setup_text;
                return 1;
            }
            if (geteuid() != 0)
                throw std::runtime_error("Run live input with sudo");
            if (lstat("/Library/Application Support/org.pqrs/tmp/rootonly/"
                      "karabiner_virtual_hid_device_service.sock",
                      &status) ||
                !S_ISSOCK(status.st_mode)) {
                throw std::runtime_error(
                    "Driver daemon socket missing: the driver is not approved or its daemon "
                    "is not running.\nCheck: sudo launchctl print "
                    "system/com.github.bdombro.virtual-hid-driver.daemon\n"
                    "Setup steps:\n" +
                    std::string(driver_setup_text));
            }
            device = std::make_unique<Device>(from_stdin || !command->move,
                                              from_stdin || command->move.has_value());
            device->wait_ready();
        }
        const auto execute = [&](const Command& action) {
            if (action.move) {
                if (device)
                    move_pointer(*device, *action.move);
                std::cout << (dry_run ? "validated move" : "ok") << std::endl;
            } else {
                for (const auto& chord : action.chords) {
                    check_interrupted();
                    if (device)
                        device->tap(parse_chord(chord));
                    std::cout << (dry_run ? "validated " + chord : "ok") << std::endl;
                }
            }
        };
        if (from_stdin) {
            std::cout << "ready" << std::endl;
            std::string line;
            while (!interrupted && std::getline(std::cin, line)) {
                std::istringstream input(line);
                std::vector<std::string> tokens;
                for (std::string token; input >> token;)
                    tokens.push_back(token);
                execute(parse_command(std::move(tokens)));
            }
            if (!std::cin.eof() && !interrupted)
                throw std::runtime_error("Cannot read stdin");
        } else {
            execute(*command);
        }
        return interrupted ? 130 : 0;
    } catch (const std::exception& error) {
        std::cerr << "macos-input: " << error.what() << '\n';
        return interrupted ? 130 : 1;
    }
}
