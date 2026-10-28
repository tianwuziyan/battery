#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *battery_binary = "/usr/local/co.palokaj.battery/battery";
static io_connect_t power_connection;

static int run_battery_event(const char *event) {
    pid_t pid = fork();
    if (pid < 0) {
        return errno;
    }
    if (pid == 0) {
        execl(battery_binary, battery_binary, "sleep_event", event, NULL);
        _exit(127);
    }

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) {
            return errno;
        }
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

static void power_callback(void *context, io_service_t service,
                           natural_t message_type, void *message_argument) {
    (void)context;
    (void)service;

    switch (message_type) {
    case kIOMessageCanSystemSleep:
        IOAllowPowerChange(power_connection, (intptr_t)message_argument);
        break;
    case kIOMessageSystemWillSleep:
        if (run_battery_event("prepare") != 0) {
            fprintf(stderr, "battery sleep protection failed before sleep\n");
        }
        IOAllowPowerChange(power_connection, (intptr_t)message_argument);
        break;
    case kIOMessageSystemHasPoweredOn:
        if (run_battery_event("wake") != 0) {
            fprintf(stderr, "battery sleep protection failed after wake\n");
        }
        break;
    default:
        break;
    }
}

int main(void) {
    IONotificationPortRef notification_port = NULL;
    io_object_t notifier = IO_OBJECT_NULL;

    power_connection = IORegisterForSystemPower(
        NULL, &notification_port, power_callback, &notifier);
    if (power_connection == IO_OBJECT_NULL || notification_port == NULL) {
        fprintf(stderr, "failed to register for macOS power notifications\n");
        return 1;
    }

    CFRunLoopSourceRef source =
        IONotificationPortGetRunLoopSource(notification_port);
    if (source == NULL) {
        fprintf(stderr, "failed to create power notification run loop\n");
        IODeregisterForSystemPower(&notifier);
        IOServiceClose(power_connection);
        IONotificationPortDestroy(notification_port);
        return 1;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRunLoopRun();

    IODeregisterForSystemPower(&notifier);
    IOServiceClose(power_connection);
    IONotificationPortDestroy(notification_port);
    return 0;
}
