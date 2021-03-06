
# stop script on error
set -e

REGION=${1:-us-east-1}
ENV=${2:-dev}
export AWS_DEFAULT_REGION=$REGION

# Setup build directory
rm -rf ./build
mkdir ./build

# Check to see if root CA file exists, download if not
if [ ! -f ./roveros/certs/root-CA.crt ]; then
  printf "\nDownloading AWS IoT Root CA certificate from Symantec...\n"
  curl https://www.amazontrust.com/repository/AmazonRootCA1.pem > ./roveros/certs/root-CA.crt
fi

# generate cert and key
if [ ! -f ./roveros/certs/cert.pem ]; then
    printf "\nGenerating AWS IoT keys and certificates...\n"
    CERTIFICATE_ARN=$(aws iot create-keys-and-certificate --set-as-active --certificate-pem-outfile=./roveros/certs/cert.pem --public-key-outfile=./roveros/certs/public.key --private-key-outfile=./roveros/certs/private.key --query certificateArn --output text)

    if [ $? -ne 0 ]
    then
        printf "\nUnable to get Certificate ARN for Policy Attachment...Exiting.\n"
        exit 255
    fi

    printf "\nAttaching Policy default-roborover-policy to ${CERTIFICATE_ARN} ARN...\n"

    aws iot attach-policy --policy-name default-roborover-policy --target ${CERTIFICATE_ARN}

fi

#ENDPOINT=$(aws iot describe-endpoint --query endpointAddress --output text)
ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)

# Check to see if anything was returned
if [ $? -ne 0 ]
then
  printf "\nUnable to find AWS IoT Endpoint...\n"
    exit 255
fi

printf "\nFound AWS IoT Endpoint: ${ENDPOINT}...\n"

# https://q0lh864dc2.execute-api.${REGION}.amazonaws.com/dev/api/recognize

RECOGNITION_API_MODEL=$(aws apigateway get-rest-apis --query 'items[?contains(name, `acg-roborover`) == `true`].id' --output text)

# Check to see if anything was returned
if [ $? -ne 0 ]
then
  printf "\nUnable to find AWS API Gateway Endpoint for Image Recognition...\n"
    exit 255
fi

RECOGNITION_ENDPOINT="https://${RECOGNITION_API_MODEL}.execute-api.${REGION}.amazonaws.com/${ENV}/api/recognize"

printf "\nAWS API Gateway Endpoint for Image Recognition: ${RECOGNITION_ENDPOINT}...\n"

touch ./roveros/config/bootstrap.json

echo "{
  \"endpoint\": \"${ENDPOINT}\",
  \"recognition_endpoint\": \"${RECOGNITION_ENDPOINT}\"
}" > ./roveros/config/bootstrap.json

# Zip it
zip -r ./build/roborover.zip ./roveros -x ./roveros/node_modules/**\* ./roveros/*.git*

ssh -tt pi@dex.local << EOT
rm -rf rovertemp
rm -rf roveros
mkdir rovertemp
exit
EOT

# copy
scp ./build/roborover.zip pi@dex.local:rovertemp/

ssh -tt pi@dex.local << EOT
cd rovertemp
unzip roborover.zip
mv roveros /home/pi
cd /home/pi/roveros
npm install
exit
EOT

# expect -c 'spawn ssh user@server "ls -lh file"; expect "assword:"; send "mypassword\r"; interact'

# pip install picamera