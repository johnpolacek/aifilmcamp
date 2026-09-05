export async function GET() {
  return Response.json(
    { error: "Project posts and post exports have been retired." },
    { status: 410 }
  );
}
