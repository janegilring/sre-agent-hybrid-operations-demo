# Security and safe feedback

Never submit secrets, operational bindings, private addresses, actual environment
paths, raw logs, support bundles, internal URLs or personal data in this repository.
Use synthetic fixtures when reporting issues.

Report suspected sensitive disclosure through the owner's established private
security channel or GitHub private vulnerability reporting if enabled; this file
does not claim that reporting is configured. Stop distribution pending review.
Credential revocation/incident response is separate from removing Git content.

Deployment, cleanup and the optional fixed Spooler start can change live systems;
follow each component's scope and approval requirements. Do not add a broad executor,
fault injector or cleanup command without explicit scope/approval, exact target
guards, reversible behavior and tests. Do not expose exercise fixtures/answers
to the investigating agent through knowledge or broadly authorized GitHub tools.
