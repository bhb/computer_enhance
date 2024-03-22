const time = @cImport({
    @cInclude("sys/time.h");
});

pub fn readOSTimer() i64 {
    var value = time.timeval{
        .tv_sec = 0, // Seconds
        .tv_usec = 0, // Microseconds
    };

    _ = time.gettimeofday(&value, null);

    return value.tv_sec;
}
