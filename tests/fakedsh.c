// fakedsh: pretends to be `dsh web --port N`. Env knobs:
//   FAKEDSH_IGNORE_TERM=1   ignore SIGTERM (forces SIGKILL escalation)
//   FAKEDSH_EXIT_AFTER=N    exit(3) after N seconds of serving (crash simulation)
//   FAKEDSH_SPAWN_CHILD=1   spawn a `sleep 600` child in the same process group (orphan test)
//   FAKEDSH_DELAY=N         wait N seconds before listening (readiness test)
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>

static void ignore(int s) { (void)s; }

int main(int argc, char **argv) {
    int port = 3080;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--port") && i + 1 < argc) port = atoi(argv[i + 1]);
    if (argc > 1 && !strcmp(argv[1], "--version")) { puts("0.1.0-fake"); return 0; }
    if (getenv("FAKEDSH_IGNORE_TERM")) signal(SIGTERM, ignore);
    if (getenv("FAKEDSH_SPAWN_CHILD")) { if (fork() == 0) { execl("/bin/sleep", "sleep", "600", (char *)0); _exit(1); } }
    if (getenv("FAKEDSH_DELAY")) sleep(atoi(getenv("FAKEDSH_DELAY")));
    int fd = socket(AF_INET, SOCK_STREAM, 0), one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a = {0}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = inet_addr("127.0.0.1");
    if (bind(fd, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 2; }
    listen(fd, 16);
    fprintf(stderr, "fakedsh: listening on %d pid %d\n", port, getpid());
    time_t start = time(NULL); int exit_after = getenv("FAKEDSH_EXIT_AFTER") ? atoi(getenv("FAKEDSH_EXIT_AFTER")) : 0;
    const char *resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 27\r\nConnection: close\r\n\r\n<html><body>fake</body></html>";
    for (;;) {
        fd_set rf; FD_ZERO(&rf); FD_SET(fd, &rf); struct timeval tv = {0, 200000};
        int r = select(fd + 1, &rf, NULL, NULL, &tv);
        if (exit_after && time(NULL) - start >= exit_after) { fprintf(stderr, "fakedsh: simulated crash\n"); return 3; }
        if (r <= 0) continue;
        int c = accept(fd, NULL, NULL); if (c < 0) continue;
        char buf[2048]; (void)!read(c, buf, sizeof buf); (void)!write(c, resp, strlen(resp)); close(c);
    }
}
