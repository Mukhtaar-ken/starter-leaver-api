# Starter/Leaver API

A small cloud service that sets up a new starter's account, or closes down a leaver's,
in Microsoft Entra ID. Safe to run twice: it only does the steps that are still needed.

**Status: in progress.** So far: the logic that works out what to do, with tests.
Next: carrying out the steps through Microsoft Graph, then hosting it as an Azure Function.

All testing uses a practice tenant with fake users.
