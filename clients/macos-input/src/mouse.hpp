#pragma once
#include <algorithm>
#include <cerrno>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>
#ifdef __APPLE__
#include <xlocale.h>
#else
#include <locale.h>
#endif

namespace macos_input {
struct Point {
    double x = 0;
    double y = 0;
};

struct Bounds {
    double x, y, width, height;
    bool contains(Point point) const {
        return point.x >= x && point.y >= y && point.x < x + width && point.y < y + height;
    }
};

struct Delta {
    int x, y;
};

enum class Coordinates { relative, absolute, percent };
struct Move {
    Coordinates coordinates;
    Point position;
    double seconds = 0;
};

inline double number(const std::string& value) {
    const bool invalid_syntax =
        value.empty() || value.front() == '+' ||
        std::isspace(static_cast<unsigned char>(value.front())) ||
        value.find_first_of("xX") != std::string::npos;
    const auto locale = newlocale(LC_NUMERIC_MASK, "C", nullptr);
    if (!locale)
        throw std::runtime_error("Cannot initialize the numeric locale");
    char* end = nullptr;
    errno = 0;
    const double result = strtod_l(value.c_str(), &end, locale);
    const int error = errno;
    freelocale(locale);
    if (invalid_syntax || end != value.data() + value.size() || !std::isfinite(result) ||
        (error == ERANGE && result == 0))
        throw std::runtime_error("Expected a finite number: " + value);
    return result;
}

inline Move parse_move(const std::vector<std::string>& args) {
    if ((args.size() != 4 && args.size() != 6) || args[0] != "move")
        throw std::runtime_error("Use move relative|absolute|percent X Y [--smooth SECONDS]");
    Coordinates coordinates;
    if (args[1] == "relative")
        coordinates = Coordinates::relative;
    else if (args[1] == "absolute")
        coordinates = Coordinates::absolute;
    else if (args[1] == "percent")
        coordinates = Coordinates::percent;
    else
        throw std::runtime_error("Unknown coordinate mode: " + args[1]);
    Move move{coordinates, {number(args[2]), number(args[3])}};
    if (args.size() == 6) {
        if (args[4] != "--smooth")
            throw std::runtime_error("Expected --smooth SECONDS");
        move.seconds = number(args[5]);
        if (move.seconds < 0)
            throw std::runtime_error("Smooth duration cannot be negative");
    }
    for (double value : {move.position.x, move.position.y}) {
        if (coordinates == Coordinates::percent && (value < 0 || value > 100))
            throw std::runtime_error("Percentage coordinates must be between 0 and 100");
        if (coordinates == Coordinates::relative &&
            (std::trunc(value) != value || value < std::numeric_limits<int32_t>::min() ||
             value > std::numeric_limits<int32_t>::max()))
            throw std::runtime_error(
                "Relative coordinates must be signed 32-bit integer HID counts");
    }
    return move;
}

inline Point percent_target(Bounds display, Point percent) {
    return {display.x + (display.width - 1) * percent.x / 100,
            display.y + (display.height - 1) * percent.y / 100};
}

inline double progress(double elapsed, double seconds) {
    if (seconds == 0)
        return 1;
    const double t = std::clamp(elapsed / seconds, 0.0, 1.0);
    return t * t * (3 - 2 * t);
}

inline Point interpolate(Point start, Point end, double fraction) {
    return {start.x + (end.x - start.x) * fraction, start.y + (end.y - start.y) * fraction};
}

inline bool reached(Point current, Point target) {
    return std::abs(current.x - target.x) <= 0.5 && std::abs(current.y - target.y) <= 0.5;
}

inline Delta relative_step(int64_t x, int64_t y) {
    const double scale = std::max(
        {1.0, std::abs(static_cast<double>(x)) / 127, std::abs(static_cast<double>(y)) / 127});
    return {static_cast<int>(std::lround(x / scale)), static_cast<int>(std::lround(y / scale))};
}

inline int correction(double error, double gain) {
    if (std::abs(error) <= 0.5)
        return 0;
    const auto value = static_cast<int>(std::lround(std::clamp(error / gain, -127.0, 127.0)));
    return value == 0 ? (error < 0 ? -1 : 1) : value;
}
} // namespace macos_input
