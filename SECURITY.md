# Security policy

## Reporting a vulnerability

Please report security problems **privately**, not in public issues or pull requests.

- Use GitHub's **Report a vulnerability** button on the repository's Security tab (private advisory), or
- email **admin@hillcraft-sc.com** with "OneRoot security" in the subject.

Include the OneRoot version and platform, steps to reproduce, and the impact you see. If you have a proof of concept, keep it minimal and don't use real user data.

## What to expect

- Acknowledgement within about 7 days.
- A fix or mitigation plan once the issue is confirmed, with updates as it progresses.
- Credit in the release notes if you want it.

Please give us a reasonable time to ship a fix before disclosing publicly. OneRoot is maintained by one person, so timelines are best-effort.

## Scope

In scope: the OneRoot Mac and Linux apps and this repository's code and scripts: file-operation bugs that could lose or expose data, path or permission handling, archive and network-share handling, credential storage, and the release and packaging scripts.

Out of scope: issues that require an already-compromised machine, and vulnerabilities in third-party software or the OS itself (report those upstream).

## Supported versions

Only the latest release of each platform receives security fixes.
