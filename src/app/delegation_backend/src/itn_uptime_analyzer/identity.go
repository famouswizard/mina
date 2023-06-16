package itn_uptime_analyzer

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	dg "block_producers_uptime/delegation_backend"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	logging "github.com/ipfs/go-log/v2"
)

type Identity map[string]string

// Goes through each submission and adds an identity type to a map

func CreateIdentities(ctx dg.AwsContext, log *logging.ZapEventLogger) map[string]Identity {

	currentTime := GetCurrentTime()
	currentDateString := currentTime.Format(time.RFC3339)[:10]
	lastExecutionTime := GetLastExecutionTime(currentTime)

	prefixCurrent := strings.Join([]string{ctx.Prefix, "submissions", currentDateString}, "/")

	identities := make(map[string]Identity) // Create a map for unique identities

	var submissionData dg.MetaToBeSaved

	input := &s3.ListObjectsV2Input{
		Bucket: ctx.BucketName,
		Prefix: &prefixCurrent,
	}

	// Paginate through ListObjects results

	paginator := s3.NewListObjectsV2Paginator(ctx.Client, input)

	for paginator.HasMorePages() {
		page, err := paginator.NextPage(ctx.Context)
		if err != nil {
			log.Fatalf("Getting next page of paginator (BPU bucket): %v\n", err)
		}

		for _, obj := range page.Contents {
			submissionTime, err := time.Parse(time.RFC3339, (*obj.Key)[32:52])
			if err != nil {
				log.Fatalf("Error parsing time: %v\n", err)
			}

			if (submissionTime.After(lastExecutionTime)) && (submissionTime.Before(currentTime)) {

				objHandle, err := ctx.Client.GetObject(ctx.Context, &s3.GetObjectInput{
					Bucket: ctx.BucketName,
					Key:    obj.Key,
				})

				if err != nil {
					log.Fatalf("Error getting object from bucket: %v\n", err)
				}

				defer objHandle.Body.Close()

				objContents, err := io.ReadAll(objHandle.Body)
				if err != nil {
					log.Fatalf("Error getting creating reader for json: %v\n", err)
				}

				err = json.Unmarshal(objContents, &submissionData)
				if err != nil {
					log.Fatalf("Error unmarshaling bucket content: %v\n", err)
				}

				identity := GetIdentity(submissionData.Submitter.String(), submissionData.RemoteAddr)
				if _, inMap := identities[identity["id"]]; !inMap {
					AddIdentity(identity, identities)
					fmt.Printf("Submitter: %s", submissionData.Submitter.String())
				}
			}
		}
	}
	return identities
}

// Returns and Identity type identified by a hash value as an id

func GetIdentity(pubKey string, ip string) Identity {
	s := strings.Join([]string{pubKey, ip}, "-")
	id := md5.Sum([]byte(s)) // Create a hash value and use it as id

	identity := map[string]string{
		"id":         hex.EncodeToString(id[:]),
		"public-key": pubKey,
		"public-ip":  ip,
	}

	return identity
}

// Adds an identity to the map

func AddIdentity(identity Identity, identities map[string]Identity) {
	identities[identity["id"]] = identity
}
