#include "mouse.hpp"
#include <iostream>

using namespace macos_input;

void require(bool condition, const char *message) {
    if (!condition)
        throw std::runtime_error(message);
}

int main() {
    try {
        require(number("-1.25e2") == -125 && number("1e-320") > 0,
                "decimal exponents and representable subnormals remain accepted");
        const auto move = parse_move({"move", "relative", "-400", "250"});
        require(move.seconds == 0 && move.position.x == -400, "instant relative move");
        int64_t x = -400, y = 250, total_x = 0, total_y = 0;
        while (x || y) {
            const auto delta = relative_step(x, y);
            require(std::abs(delta.x) <= 127 && std::abs(delta.y) <= 127, "HID report limit");
            require(delta.x || delta.y, "chunking must make progress");
            total_x += delta.x;
            total_y += delta.y;
            x -= delta.x;
            y -= delta.y;
        }
        require(total_x == -400 && total_y == 250, "relative deltas must sum exactly");

        const Bounds display{-1920, -100, 1920, 1080};
        const auto corner = percent_target(display, {100, 100});
        require(corner.x == -1 && corner.y == 979 && display.contains(corner),
                "100 percent stays inside a display with a negative origin");
        const auto origin = percent_target(display, {0, 0});
        require(origin.x == -1920 && origin.y == -100, "zero percent uses display origin");
        require(progress(0, 0) == 1 && progress(0, 1) == 0 && progress(1, 1) == 1,
                "animation endpoints");
        require(std::abs(progress(0.25, 1) - 0.15625) < 1e-9, "smooth ease-in");
        require(reached({10.5, 9.5}, {10, 10}) && !reached({10.51, 10}, {10, 10}),
                "absolute arrival tolerance is half a screen point");

        Point current{0, 0};
        const Point target{300, -100};
        Point gain{1, 1};
        for (int i = 0; i < 20 && !reached(current, target); ++i) {
            const Delta step{correction(target.x - current.x, gain.x),
                             correction(target.y - current.y, gain.y)};
            current.x += step.x * 2;
            current.y += step.y * 2;
            gain = {2, 2};
        }
        require(reached(current, target), "feedback compensates for pointer acceleration");

        for (const auto &args : std::vector<std::vector<std::string>>{
                 {"move", "percent", "101", "0"},
                 {"move", "percent", "-1", "0"},
                 {"move", "relative", "1.5", "0"},
                 {"move", "absolute", "nan", "0"},
                 {"move", "relative", "2147483648", "0"},
                 {"move", "absolute", "inf", "0"},
                 {"move", "absolute", "1junk", "0"},
                 {"move", "absolute", "1,5", "0"},
                 {"move", "absolute", " 1", "0"},
                 {"move", "absolute", "+1", "0"},
                 {"move", "absolute", "0x1p2", "0"},
                 {"move", "absolute", "1e5000", "0"},
                 {"move", "absolute", "1e-5000", "0"},
                 {"move", "absolute", "1", "2", "--smooth", "-1"},
                 {"move", "absolute", "1", "2", "--smooth", "nan"},
                 {"move", "relative", "1"},
                 {"move", "unknown", "1", "2"}}) {
            bool rejected = false;
            try {
                parse_move(args);
            } catch (const std::runtime_error &) {
                rejected = true;
            }
            require(rejected, "invalid movement accepted");
        }
        std::cout << "Mouse parsing, geometry, chunking and feedback tests passed without input.\n";
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
