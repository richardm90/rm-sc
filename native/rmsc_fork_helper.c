/*
 * rmsc_fork_helper <jobname> <command>
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
 */

#include <as400_protos.h>
#include <fcntl.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
  int devnull;

  if (argc < 3) {
    return 1;
  }

  if (f_fork400(argv[1], 0) != 0) {
    /* parent: the transient glue job. nothing more to do. */
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
