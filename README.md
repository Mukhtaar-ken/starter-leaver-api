# Starter/Leaver API

A small cloud service that sets up a new starter's account, or closes down a leaver's,
in Microsoft Entra ID. Send it one HTTP request and it does the rest. It's safe to run twice,
because it only does the steps that are still needed.

All testing uses a practice tenant with fake users.

## Why I built it

Setting up starters and closing down leavers by hand is slow and easy to get wrong:
a missed group, or an account left able to sign in. I wanted to learn how to automate it
properly, in the cloud, with tests and without storing secrets.

## How it works

```
HTTP POST ──► Azure Function (PowerShell 7.4)
                 │  1. check the request
                 │  2. read what already exists in Entra
                 │  3. work out only the missing steps
                 │  4. carry them out
                 ▼
            Microsoft Graph ──► Entra ID (users and groups)
```

The function signs in to Graph with its own **managed identity**, so there is no password,
secret or certificate anywhere in the code or the settings.

### Starter

`POST /api/starter`

```json
{ "firstName": "Jane", "lastName": "Doe", "employeeId": "E1001", "department": "Sales" }
```

Steps: create the user (random password, must change it at first sign-in), switch the account on
if it's off, and add the groups for that department (`config/departments.json`).

### Leaver

`POST /api/leaver`

```json
{ "employeeId": "E1001" }
```

Steps: block sign-in, sign the user out everywhere (revoke sessions), and remove them from their groups.
The account is kept, not deleted.

### Responses

| Code | Meaning |
|---|---|
| 200 | Done, with the list of steps taken. An empty list means there was nothing left to do |
| 400 | The request was missing something or invalid |
| 404 | Leaver not found |
| 409 | That sign-in address already belongs to a different employee |
| 500 | Anything else. Details go to the logs, not to the caller |

## Safety built in

- **Plan, then act.** `Get-StarterAction` and `Get-LeaverAction` compare what is wanted with what exists
  and return only the missing steps. Running the same request twice does nothing the second time (idempotent).
- **Tenant guard.** The code refuses to change anything unless Graph is signed in to the tenant it was given,
  so it can't change the wrong tenant by accident.
- **Allows for Entra lag.** Entra can be a few seconds behind itself after a change, so "already done" errors
  count as done and a just-created user is retried briefly (see "What broke" below).
- **Least privilege.** The managed identity only has `User.ReadWrite.All` and `GroupMember.ReadWrite.All`.
- **`-WhatIf`.** Run locally, the module shows what it would do without doing it.

## What's in Azure

All of it is defined in `infra/main.bicep`. Re-deploying only changes what differs.

| Resource | Why |
|---|---|
| Function App (Consumption plan) | Runs the code. Pay per run, nothing when idle |
| Managed identity | The app's own identity in Entra, used to call Graph |
| Storage account | Bookkeeping the Functions runtime needs (HTTPS only, no public access) |
| Log Analytics + Application Insights | Logs and request history, to investigate failures |

## Run the tests

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
Invoke-Pester ./tests -Output Detailed
```

53 tests. Graph is mocked, so nothing touches a real tenant.
GitHub Actions runs them on every pull request, along with PSScriptAnalyzer and a Bicep compile check.

## Deploy

```powershell
az login --tenant <tenant id>
.\deploy\deploy.ps1 -TenantId <tenant id> -UserDomain <yourtenant>.onmicrosoft.com
.\deploy\grant-graph-permissions.ps1   # once, gives the managed identity its two Graph permissions
```

Callers need the function key: `az functionapp keys list -g rg-starter-leaver-api -n <function app>`.

## What broke, and what I learned

- **"Safe to run twice" failed if you ran it twice quickly, and my first fix was wrong.** In the live test,
  the same starter request sent one second after the first returned an error. Minutes later it correctly said "nothing to do".
  My first theory was that only Graph's search index (`ConsistencyLevel: eventual`) lagged, so I switched that one lookup
  to a plain filter (v0.3.1). The next live test failed the same way, and a leaver sent straight after found the user
  by employee ID, then *couldn't* find them by sign-in address a second later.
  The real cause: Entra keeps several copies of the directory, and they take a few seconds to agree after a change.
  Any read straight after a write can miss it (**eventual consistency**). So "check what exists, then act" can't be
  fully trusted. v0.4.0 allows for it:
  - Graph saying "already exists" (user or group member) or "not found" (removing a member) counts as **already done**.
    If the address is taken, it checks it's the same employee before carrying on; if not, it stops with a 409.
  - The user's ID from the first lookup is **carried through**, instead of looking them up again.
  - A brand-new user that isn't visible yet is **retried** a few times, 2 seconds apart.

  Lessons: mocked tests only test what you assume Graph does, so a live test still matters. And test a fix
  against the real thing before believing your theory about why it broke.
- **The tests found a real gap.** If Graph returned a user with a blank ID, the code would have carried on
  and tried to change "nobody". It now stops.
- **Warnings looked like failures.** `az` writes harmless warnings to the error stream, and Windows PowerShell 5.1
  treated them as errors, so the first deploy stopped halfway. The deploy script now judges `az` by its exit code.
- **No room in the region.** My free subscription had a quota of 0 for the Consumption plan in UK South and North Europe.
  The deploy script now lets the resources live in a different region from the resource group (UK West worked).
- **Sign-in quirks.** Device-code sign-in is blocked when security defaults are on, and `Connect-MgGraph`
  fails when there's no console window. Both are worth knowing before you automate a sign-in.

## What I'd change next

- **Sign callers in with Entra ID instead of a function key.** A key is a shared secret, and anyone who has it can call the API.
- **Deploy from GitHub Actions using OIDC**, so a merge to `main` deploys with no stored secrets.
- **Connect to storage with the managed identity** instead of the account key in the app settings.
- **Add an audit trail**: who asked for each change, and when.
