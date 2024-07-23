const std = @import("std");
const platform = @import("./platform.zig");

pub const RepetitionTester = struct {
    pub fn init() RepetitionTester {
        return RepetitionTester{};
    }

    pub fn is_testing(self: *RepetitionTester) bool {
        _ = self;
        return false;
    }
};
