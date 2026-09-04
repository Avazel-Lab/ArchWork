# Using an ArchWork machine

What to do with the machine once it is built. `first-install.md` covers building it.

Everything here runs on the machine itself. Nothing needs another computer.

---

## The keys

The wallpaper is the cheat sheet. It is generated from the file that binds the keys, so it cannot drift from them.

| Keys | What happens |
|---|---|
| `Super` + `Return` | terminal |
| `Super` + `D` | application launcher |
| `Super` + `Q` | close the window |
| `Super` + `F` | fullscreen |
| `Super` + `V` | float or tile |
| `Super` + `L` | lock the screen |
| `Super` + `Shift` + `E` | exit to the greeter |
| `Print` | screenshot into `~/Pictures/screenshots` |
| `Super` + arrows | move focus |
| `Super` + `1`…`9` | switch workspace |
| `Super` + `Shift` + `1`…`9` | send the window to a workspace |

---

## Updating

```bash
archwork-update
```

Five steps, in this order, stopping at the first failure in steps 1 to 4:

1. a pre-update Btrfs snapshot, through btrbk
2. Arch packages, `pacman -Syu`
3. AUR packages, built in the clean chroot
4. configuration, by running the playbook against this machine
5. health checks

Step 5 always runs, even after a failure, because a machine that stopped halfway is exactly the one worth checking.

Useful flags: `--dry-run` says what each step would do and changes nothing. `--skip-aur` does Arch packages only. `--skip-reconcile` leaves configuration alone.

**The snapshot is the point.** If an update goes wrong, the way back is already on disk. `archwork-update` refuses to run without one unless you pass `--no-snapshot` deliberately.

---

## Checking the machine

```bash
archwork-health
```

Asserts that the machine still matches what the repository describes: subvolume mounts and their boundaries, the encryption state, both Unified Kernel Images, the services that have to be up, and the idle timings. Exits non-zero if anything failed, so it can gate something else. `--quiet` prints only failures and the summary.

Run it after an update, after a rollback, or whenever something feels wrong.

---

## Going back

```bash
archwork-rollback list
archwork-rollback to SNAPSHOT
```

Replaces the root subvolume with a writable copy of a snapshot. Reboot afterwards.

Two things worth knowing before you need them:

- **The old root is kept**, as `@.broken-TIMESTAMP`, so a bad rollback can itself be undone. Delete it by hand once you are satisfied.
- **Only `@` is touched.** `/home`, `@var_log`, `@var_cache`, `@ai_models` and `@swap` are outside the rollback boundary and are left alone. Your work in `/home` survives a rollback. It is also not protected by one.

`--dry-run` prints what would happen. If the machine will not boot far enough to run this, the boot menu has a recovery entry that reaches a rescue shell with the same command on it.

---

## Staying awake

```bash
archwork-inhibit 1h        # or 2h, 4h, indefinite
archwork-inhibit --status
archwork-inhibit --cancel
```

Suppresses sleep only. The display still dims and still switches off, which is deliberate: a machine that is downloading something does not need its screen on.

---

## What a rebuild does not bring back

The machine is reproducible. A few things on it are not, by choice, and they are worth knowing because a rebuild is meant to be cheap.

- **`/home`.** Outside the rollback boundary and outside the build. Nothing in this repository writes to it without being told to. It is also not backed up by anything yet.
- **Logins and tokens.** Browser profiles, Claude Code's authentication, anything you signed into.
- **SSH private keys.** Deliberately not in the repository's encrypted set: putting them there would widen what one passphrase protects, for no gain. Generate a new key on the machine and add it to the account it needs to reach.
- **Codex CLI.** Installed by hand with `npm install -g @openai/codex`, because the unofficial AUR packaging is not trusted enough to sit in an unattended rebuild path. Repeat it after a rebuild.

Everything else should arrive from the repository. **If you fix something by hand and want to keep it, say so, and it goes into the repository before the next rebuild.** A fix that lives only on the machine disappears the next time it is rebuilt, and rebuilding is the entire point.

---

## Software pinned on purpose

Most packages track their Arch or AUR version and update with `archwork-update`. A few are pinned to an exact version in the repository instead, so that an update never brings a surprise from upstream.

Updating one of those is a deliberate act, not something `archwork-update` does for you:

1. Change the pinned version in the repository.
2. Commit it, so the machine's state stays traceable to a commit.
3. Run `archwork-update`, which reconciles configuration in step 4 and picks the new version up.

That is the whole process, and it is the same one for anything pinned. If a pin is holding you back, the fix is to move the pin, not to work around it on the machine.

---

## Getting back to Kubuntu or Windows

Press **F8** at the ASUS logo and pick the one you want.

Kubuntu is the default boot entry, so an ArchWork machine that will not start costs you nothing: reboot and you are back where you were. `first-install.md` has the `efibootmgr` step that sets that up, and the same command changes it back.
