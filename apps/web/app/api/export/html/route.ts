export async function POST() {
  return Response.json(
    { error: "Project posts and post exports have been retired." },
    { status: 410 }
  );
}
