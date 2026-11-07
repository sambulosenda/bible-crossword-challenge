/**
 * www → apex. `www.biblecrosswordchallenge.com` served a full duplicate of the
 * site (canonicals pointed at the apex, but crawlers still saw two copies).
 * Pages `_redirects` matches paths only, never hostnames, so the redirect lives
 * here. Every other request passes straight through.
 */
export const onRequest: PagesFunction = async (context) => {
  const url = new URL(context.request.url);
  if (url.hostname === 'www.biblecrosswordchallenge.com') {
    url.hostname = 'biblecrosswordchallenge.com';
    return Response.redirect(url.toString(), 301);
  }
  return context.next();
};
