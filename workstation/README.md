# Workstation git + GitHub setup

Templates for the machine you work *from* (bazzite-prime), not the server.
Mirrors the pattern in `tomigorn/Laptop-MacOs/multiple-git-accounts`.

## Install

```bash
cp workstation/gitconfig          ~/.gitconfig
cp workstation/gitconfig-private  ~/.gitconfig-private
```

## How it works

`~/.gitconfig` has **no `[user]` block on purpose**. Identity is applied only
inside the directory trees named by `includeIf`, so a commit attempted anywhere
else fails until an identity is set explicitly. That is the point: it makes
committing as the wrong person an error rather than a silent mistake.

| Path | Identity |
|---|---|
| `~/Projects/**` | tomigorn |
| `~/development/private/**` | tomigorn (kept for parity with the Mac layout) |
| anywhere else | none — commits refuse until set |

## Keys

**One keypair, used for two distinct GitHub roles:**

| File | Purpose |
|---|---|
| `~/.ssh/gitHub-Tomigorn` | private — SSH auth to push/pull, and to sign commits |
| `~/.ssh/gitHub-Tomigorn.pub` | public — uploaded to GitHub **twice** |
| `~/.ssh/allowed_signers-private` | lets *you* verify your own signatures locally |

⚠️ The public key must be added to GitHub **twice**, once per type:
Settings → SSH and GPG keys → **New SSH key**, then again as
**New SSH signing key**. They are separate lists. Adding only the
authentication key means pushes work but commits show as *Unverified*.

## Signing

Uses **SSH signing** (`gpg.format = ssh`), not GPG — no keyring to manage, and
the same key already used for auth. `commit.gpgsign` and `tag.gpgsign` are both
true, so signing is automatic rather than something to remember.

Verify locally:

```bash
git log --show-signature -1
```

`allowedSignersFile` is what makes that print *"Good signature"* rather than
*"No principal matched"* — without it git can sign but cannot verify.
