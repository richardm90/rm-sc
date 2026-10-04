/*
 * rmsc_fork_helper <jobname> <command> [resourceID]
 *
 * resourceID is optional, defaults to 0 (automatic OS selection, what
 * SCLAUNCH_fork_command always passes implicitly by omitting it) - exposed
 * as a real argument, not hardcoded, because it's a genuine parameter of
 * f_fork400() itself, and because an out-of-range value is also the
 * cleanest known way to force f_fork400() to fail on demand for testing
 * (MEASURED: resourceID 999999999 fails reliably, "Error 3489 occurred",
 * with no effect on any shared system limit - ulimit -u does not reach
 * f_fork400() at all, tried and rejected before this).
 *
 * Names and backgrounds a non-batch service's job the way upstream's direct
 * fork() does, which rmtools' spawn()-based PASE_run_cmd cannot - MEASURED,
 * docs/parity.md ("Batch services run on a genuinely different OS mechanism
 * than upstream's"). f_fork400() is PASE-only; it cannot be called from ILE
 * RPG or ILE C (both run in the ILE/MI machine environment, not PASE), which
 * is why this exists as a separate, natively PASE-compiled artifact rather
 * than an RPGLE export - see docs/tobi-binding.md for how it's built.
 *
 * The parent is PASE_run_cmd's own transient, generically-named spawn() job
 * - it returns immediately, which is why there is nothing else for it to do
 * here. The child becomes <jobname>, and must close/redirect its inherited
 * fd 0/1/2 before exec: PASE_run_cmd reads those same pipes until EOF, and a
 * long-running child that inherits them unredirected holds PASE_run_cmd's
 * caller blocked for the service's whole life - MEASURED. <command> does
 * its own, separate redirection to the service's real log file; the
 * redirect here is only to detach from PASE_run_cmd's capture pipe, not the
 * service's real output.
 *
 * Exit codes PASE_run_cmd's own rc reflects back to SCLAUNCH_start/
 * SCEXEC_start's err text - distinct on purpose, so a failure here is not
 * silently indistinguishable from success:
 *   0   parent, f_fork400() succeeded - the child is on its own now
 *   1   wrong number of arguments
 *   2   f_fork400() itself failed (returns -1 on failure, per IBM's own
 *       documentation - NOT 0, which is the CHILD's return value; treating
 *       "not the child" as "therefore succeeded" was the bug here, found
 *       only by testing this exact failure, never by testing the happy
 *       path, however many times)
 *   127 exec() failed in the child, after f_fork400() already succeeded -
 *       the job exists under <jobname>, but never ran <command>
 */

#include <as400_protos.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Not <stdlib.h>'s strtoul() - MEASURED: <stdlib.h>'s own include chain
   (sys/wait.h -> sys/resource.h -> sys/time.h) redefines sigset_t, which
   as400_protos.h already defines via a different chain; the two conflict
   and the compile fails. A plain decimal parser avoids the whole header,
   which is all this optional, test-only argument needs. */
static unsigned
parse_decimal(const char *s)
{
  unsigned n = 0;
  while (*s >= '0' && *s <= '9') {
    n = n * 10 + (unsigned)(*s - '0');
    s++;
  }
  return n;
}

int
main(int argc, char **argv)
{
  int devnull;
  pid_t pid;
  unsigned resource_id;

  if (argc < 3) {
    return 1;
  }

  resource_id = (argc >= 4) ? parse_decimal(argv[3]) : 0u;
  pid = f_fork400(argv[1], resource_id);

  if (pid < 0) {
    /* f_fork400() failed outright - no child, no job. Report it on our own
       stdout (PASE_run_cmd's `stdout` parameter) rather than fail silent;
       the parent's fd 1 is still connected to PASE_run_cmd's capture pipe
       here, unlike the child's below. */
    fprintf(stdout, "rmsc_fork_helper: f_fork400(%s) failed: %s\n",
            argv[1], strerror(errno));
    return 2;
  }

  if (pid != 0) {
    /* parent: the transient glue job, fork succeeded. nothing more to do. */
    return 0;
  }

  /* child: nothing but the redirect and the exec. f_fork400()'s own
     documentation: "application data, mutexes and locks are all undefined
     in the child process" until exec replaces it. */
  devnull = open("/dev/null", O_RDWR);
  dup2(devnull, 0);
  dup2(devnull, 1);
  dup2(devnull, 2);

  execl("/QOpenSys/pkgs/bin/bash", "bash", "-c", argv[2], (char *)0);

  /* exec failed - the child is still alive and still named <jobname>, so
     end it rather than leave it running the wrong thing. */
  _exit(127);
}
