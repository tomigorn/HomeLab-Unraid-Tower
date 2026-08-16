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

## Key comment convention

Comments follow the existing pattern on this machine, so `ls ~/.ssh/*.pub` reads
as a list of "from here, to there":

```
|| bazzite @ bazzite-prime -> beefy
|| bazzite @ bazzite-prime -> fastpi
|| bazzite @ bazzite-prime -> tomigorn     <- this one
```

The generic form is `|| user @ computer -> target`. To change it on an existing
key, note that `ssh-keygen -y` already emits the comment stored in the private
key — appending another one duplicates it:

```bash
COMMENT="|| bazzite @ bazzite-prime -> tomigorn"
ssh-keygen -q -c -C "$COMMENT" -f ~/.ssh/gitHub-Tomigorn        # private key
printf '%s %s\n' "$(ssh-keygen -y -f ~/.ssh/gitHub-Tomigorn | awk '{print $1" "$2}')" \
  "$COMMENT" > ~/.ssh/gitHub-Tomigorn.pub                        # public key
```

⚠️ `allowed_signers-private` embeds the whole public key line, so regenerate it
whenever the key or its comment changes, or signature verification silently
stops matching.

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
