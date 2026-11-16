#define SLIMR_TEST_MAIN
#include "mouse.hpp"
#include "test.hpp"

#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

using namespace macos_input;

TEST_CASE("number accepts decimal exponents and representable subnormals") {
    CHECK(number("-1.25e2") == -125);
    CHECK(number("1e-320") > 0);
}

TEST_CASE("relative move parsing and HID report chunking") {
    const auto move = parse_move({"move", "relative", "-400", "250"});
    CHECK(move.seconds == 0);
    CHECK(move.position.x == -400);
    int64_t x = -400, y = 250, total_x = 0, total_y = 0;
    while (x || y) {
        const auto delta = relative_step(x, y);
        REQUIRE(std::abs(delta.x) <= 127);
        REQUIRE(std::abs(delta.y) <= 127);
        REQUIRE((delta.x || delta.y));
        total_x += delta.x;
        total_y += delta.y;
        x -= delta.x;
        y -= delta.y;
    }
    CHECK(total_x == -400);
    CHECK(total_y == 250);
}

TEST_CASE("percent_target clamps inside display with negative origin") {
    const Bounds display{-1920, -100, 1920, 1080};
    const auto corner = percent_target(display, {100, 100});
    CHECK(corner.x == -1);
    CHECK(corner.y == 979);
    CHECK(display.contains(corner));
    const auto origin = percent_target(display, {0, 0});
    CHECK(origin.x == -1920);
    CHECK(origin.y == -100);
}

TEST_CASE("progress and reached handle endpoints, easing, and tolerance") {
    CHECK(progress(0, 0) == 1);
    CHECK(progress(0, 1) == 0);
    CHECK(progress(1, 1) == 1);
    CHECK(std::abs(progress(0.25, 1) - 0.15625) < 1e-9);
    CHECK(reached({10.5, 9.5}, {10, 10}));
    CHECK_FALSE(reached({10.51, 10}, {10, 10}));
}

TEST_CASE("feedback loop compensates for pointer acceleration") {
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
    CHECK(reached(current, target));
}

TEST_CASE("parse_move rejects invalid movement arguments") {
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
        CHECK_THROWS_AS(parse_move(args), std::runtime_error);
    }
}
