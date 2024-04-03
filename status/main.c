#include <fcntl.h>
#include <gpiod.h>
#include <libgen.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define COMMAND_LEN 10

static struct {
    char *fifo_file;
    int daemon;
    char *gpio_chip;
    int gpio_pin;
} args;

static struct {
    int fifo_fd;
    int running;
    enum { OFF, FAST, SLOW, ON } current;
    int counter;
    struct gpiod_line_request *gpiod_line_request;
} state;

static int setup_fifo() {
    int retval = 0;
    if (!access(args.fifo_file, F_OK)) {
        if ((retval = remove(args.fifo_file))) {
            fprintf(stderr, "Removing fifo file failed: %d.\n", retval);
            goto ret;
        }
    }

    if ((retval = mkfifo(args.fifo_file, 0666))) {
        fprintf(stderr, "Creating fifo file failed: %d.\n", retval);
        goto ret;
    }

    state.fifo_fd = open(args.fifo_file, O_RDONLY | O_NONBLOCK);
    if (state.fifo_fd < 0) {
        retval = state.fifo_fd;
        fprintf(stderr, "Opening fifo file failed: %d.\n", retval);
        goto ret;
    }

ret:
    return retval;
}

static int setup_gpiod() {
    int retval = 0;
    struct gpiod_chip *chip = NULL;
    struct gpiod_line_settings *settings = NULL;
    struct gpiod_line_config *config = NULL;

    chip = gpiod_chip_open(args.gpio_chip);
    if (!chip) {
        retval = -1;
        goto ret;
    }

    settings = gpiod_line_settings_new();
    if (!settings) {
        retval = -2;
        goto ret;
    }
    gpiod_line_settings_set_direction(settings, GPIOD_LINE_DIRECTION_OUTPUT);
    gpiod_line_settings_set_output_value(settings, GPIOD_LINE_VALUE_INACTIVE);

    config = gpiod_line_config_new();
    if (!config) {
        retval = -3;
        goto ret;
    }

    if ((retval = gpiod_line_config_add_line_settings(config, &args.gpio_pin, 1,
                                                      settings))) {
        goto ret;
    }

    state.gpiod_line_request = gpiod_chip_request_lines(chip, NULL, config);

ret:
    if (config) {
        gpiod_line_config_free(config);
    }
    if (settings) {
        gpiod_line_settings_free(settings);
    }
    if (chip) {
        gpiod_chip_close(chip);
    }
    return retval;
}

static void handle_signal(int signum) { state.running = 0; }

static int close_fifo() {
    int retval;
    if (state.fifo_fd >= 0) {
        if ((retval = close(state.fifo_fd))) {
            fprintf(stderr, "Closing fifo file failed: %d.\n", retval);
            goto ret;
        }
        state.fifo_fd = -1;

        if ((retval = remove(args.fifo_file))) {
            fprintf(stderr, "Removing fifo file failed: %d.\n", retval);
            goto ret;
        }
    }

ret:
    return retval;
}

static void set_gpio(int val) {
    if (state.gpiod_line_request) {
        gpiod_line_request_set_value(state.gpiod_line_request, args.gpio_pin,
                                     val == 0 ? GPIOD_LINE_VALUE_INACTIVE
                                              : GPIOD_LINE_VALUE_ACTIVE);
    }
}

static int close_gpiod() {
    if (state.gpiod_line_request) {
        gpiod_line_request_release(state.gpiod_line_request);
        state.gpiod_line_request = NULL;
    }

    return 0;
}

static void update_led() {
    if (state.current == OFF) {
        set_gpio(0);
        printf(".\n");
    } else if (state.current == ON) {
        set_gpio(1);
        printf("O\n");
    } else {
        int factor = state.current == FAST ? 1 : 10;
        if ((state.counter / factor) % 2 == 0) {
            set_gpio(1);
            printf("O\n");
        } else {
            set_gpio(0);
            printf(".\n");
        }
    }
}

int main(int argc, char *argv[]) {
    int retval;

    args.fifo_file = NULL;
    args.daemon = 0;
    args.gpio_chip = NULL;
    args.gpio_pin = 0;

    state.fifo_fd = -1;
    state.running = 1;
    state.current = OFF;
    state.gpiod_line_request = NULL;

    /*
     * -f FIFO file
     * -d Daemon mode
     * -G gpio-chip
     * -g gpio-pin
     */
    for (;;) {
        int result = getopt(argc, argv, "f:dG:g:");
        if (result == -1)
            break;
        switch (result) {
        case 'f':
            args.fifo_file = optarg;
            break;
        case 'd':
            args.daemon = 1;
            break;
        case 'G':
            args.gpio_chip = optarg;
            break;
        case 'g':
            args.gpio_pin = atoi(optarg);
            break;
        default:
            break;
        }
    }

    if (args.fifo_file == NULL) {
        fprintf(stderr, "Need argument fifo file -f\n");
        retval = -1;
        goto ret;
    }

    /* Setup SIGTERM and SIGINT handlers */
    {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = handle_signal;
        sigaction(SIGTERM, &action, NULL);
    }
    {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = handle_signal;
        sigaction(SIGINT, &action, NULL);
    }

    printf("Setting up named pipe at %s...\n", args.fifo_file);
    setup_fifo();

    if (args.gpio_chip) {
        setup_gpiod();
    }

    if (args.daemon) {
        printf("Starting daemon...\n");
        daemon(0, 0);
    }

    printf("Main loop...\n");
    char command[COMMAND_LEN];

    state.counter = 0;
    while (state.running) {
        ssize_t r = read(state.fifo_fd, command, COMMAND_LEN);
        for (int i = 0; i < COMMAND_LEN; i++)
            if (command[i] == '\n')
                command[i] = 0;
        if (r > 0) {
            if (!strcasecmp(command, "off")) {
                state.current = OFF;
            } else if (!strcasecmp(command, "fast")) {
                state.current = FAST;
            } else if (!strcasecmp(command, "slow")) {
                state.current = SLOW;
            } else if (!strcasecmp(command, "on")) {
                state.current = ON;
            }
        }

        update_led();
        usleep(100000);
        state.counter++;
    }

ret:
    printf("Shutting down...\n");
    close_fifo();
    close_gpiod();
    return retval;
}
