#!/bin/bash
gcloud iam service-accounts add-iam-policy-binding "service-accountnewlycreated@iam.gserviceaccount.com"\
--project="${PROJECT_ID}"\ #replace with project id
--role="roles/iam.workloadIdentityUser"\
--member="principalSet://iam.googleapis.com/projects/1222646644/lcoations/global/workloadIdentityPools/my-pool/attribute.repo"