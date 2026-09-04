import { readFile } from "node:fs/promises";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  region: process.env.AWS_REGION || "us-east-1",
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
  },
});

const BUCKET = process.env.S3_BUCKET || "aifilmcamp-public";
const CLOUDFRONT_URL = process.env.CLOUDFRONT_URL;

/**
 * Upload a file to S3 and return the public URL
 */
export async function uploadToS3(
  filePath: string,
  key: string,
  contentType: string
): Promise<string> {
  console.log("[uploader] Uploading to S3:", JSON.stringify({ key, contentType }, null, 2));

  const body = await readFile(filePath);

  await s3.send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: body,
      ContentType: contentType,
    })
  );

  // Return CloudFront URL if available, otherwise S3 URL
  let url: string;
  if (CLOUDFRONT_URL) {
    url = `${CLOUDFRONT_URL}/${key}`;
  } else {
    url = `https://${BUCKET}.s3.amazonaws.com/${key}`;
  }

  console.log("[uploader] Upload complete:", JSON.stringify({ url }, null, 2));

  return url;
}
