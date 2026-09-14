# Application Default Credentials for Google client libraries and tools
# (gcloud itself uses its own credential store; this is for everything else)
if test -r ~/.config/gcloud/legacy_credentials/scott-readonly-service-account@hihellome-2f54b.iam.gserviceaccount.com/adc.json
    set -gx GOOGLE_APPLICATION_CREDENTIALS ~/.config/gcloud/legacy_credentials/scott-readonly-service-account@hihellome-2f54b.iam.gserviceaccount.com/adc.json
end
