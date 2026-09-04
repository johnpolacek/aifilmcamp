/**
 * In-memory job status store for tracking composition progress
 */

export interface JobStatus {
  jobId: string;
  status: "downloading" | "processing" | "uploading" | "completed" | "failed";
  progress: number; // 0-100
  stage: string;
  startedAt: string;
  updatedAt: string;
  error?: string;
}

// In-memory store - jobs are cleaned up after 1 hour
const jobs = new Map<string, JobStatus>();

// Cleanup interval - remove old jobs
setInterval(
  () => {
    const oneHourAgo = Date.now() - 60 * 60 * 1000;
    for (const [jobId, job] of jobs.entries()) {
      if (new Date(job.updatedAt).getTime() < oneHourAgo) {
        jobs.delete(jobId);
      }
    }
  },
  5 * 60 * 1000
); // Run every 5 minutes

export function createJob(jobId: string): JobStatus {
  const job: JobStatus = {
    jobId,
    status: "downloading",
    progress: 0,
    stage: "Initializing...",
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  jobs.set(jobId, job);
  return job;
}

export function updateJob(
  jobId: string,
  updates: Partial<Omit<JobStatus, "jobId" | "startedAt">>
): JobStatus | null {
  const job = jobs.get(jobId);
  if (!job) return null;

  const updatedJob: JobStatus = {
    ...job,
    ...updates,
    updatedAt: new Date().toISOString(),
  };
  jobs.set(jobId, updatedJob);
  return updatedJob;
}

export function getJob(jobId: string): JobStatus | null {
  return jobs.get(jobId) || null;
}

export function deleteJob(jobId: string): void {
  jobs.delete(jobId);
}
