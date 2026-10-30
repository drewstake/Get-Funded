# Thumbnail upload fails for a compliant JPEG

Test date: September 28, 2026 (America/New_York).

Experience: Get Funded!
Universe ID: 10768404077
Place ID: 137759823569682
Ownership: personal account, as confirmed by the owner.

Dashboard page:
https://create.roblox.com/dashboard/creations/experiences/10768404077/places/137759823569682/thumbnails

## Reproduction

1. Open the experience's Thumbnails page in Creator Dashboard while signed in as its owner.
2. Select Experience Detail Page.
3. Click Upload thumbnail.
4. Select `07-dont-tilt.jpeg` alone.
5. Wait for the upload to finish.

Actual result: an Upload image failed dialog appears with the following message:

> Thumbnails should be the following formats: *.jpeg, *.gif, *.png, *.tga, *.bmp and not exceed 3MB in size.

Expected result: the compliant image is accepted as a thumbnail and can be saved.

## Test file

- Location: `thumbnails/jpeg-upload/batch-2/07-dont-tilt.jpeg`
- Actual encoded format: baseline JPEG, non-progressive.
- Dimensions: 1920 by 1080, 16:9.
- File size: 368,165 bytes (well below both common interpretations of 3 MB).
- Color: three-channel sRGB, no ICC profile.
- Previous local validation: image successfully decoded.
- Exactly one file was selected.

## Additional observations

- The owner also reported failures when uploading a single image through Home Page.
- Three recent image assets named Personalized Thumbnail were visible under the owner's Development Items. Asset 112229752280970 showed the generated BIG WIN! artwork, although the Home Page thumbnail list was empty. This proves that particular image was stored as an asset; it does not prove thumbnail attachment or moderation approval.
- The in-app browser test reproduced the generic error on Experience Detail Page. No Save Changes operation was performed after that failure.
- Available browser console logs did not expose an upload-specific server response. An unrelated-looking routing warning and translation warnings were present. The precise backend cause is unconfirmed.

Evidence: `iab-jpeg-upload-failed.png` in this folder. This report has not been sent to Roblox.

## Follow-up investigation

- The test JPEG was found in Development Items > Images as a new record named **Asset Thumbnail**, ID **78274377155968**. Its rendered preview is the correct DON'T TILT! artwork. This confirms that Roblox stored the test image despite showing the upload-failed dialog.
- Asset URL: https://create.roblox.com/dashboard/creations/store/78274377155968/configure
- The asset configuration page shows Open Use. No moderation decision is displayed there.
- Evidence: `dont-tilt-stored-as-asset.png`.
- After leaving the Thumbnails page and returning, Home Page still showed the initial empty state; Experience Detail Page still had an empty thumbnail list with Save Changes disabled. Reopening the page did not recover the upload.
- The Access page displayed server size and social-slot settings; it did not show an upload restriction.

### Related primary reports

1. https://devforum.roblox.com/t/detail-experience-page-thumbnails-completely-fail-to-uploaddeleteedit/4676897/6 documents images being stored successfully while thumbnail association fails. Post 8 describes a page-refresh workaround that did not resolve our test.
2. https://devforum.roblox.com/t/upload-image-failed-for-home-page-thumbnail/4720722 documents the same generic error with a specific backend message, "The upload operation does not belong to the universe." That message was reported by another creator and has NOT been observed in this experience. The thread's last follow-up says the issue resolved without a documented user fix.
3. https://status.roblox.com/ lists a Studio publishing disruption starting September 28, 2026 at 16:05 PDT. It does not establish that Creator Dashboard thumbnail failures share that cause.

### Diagnosis and remaining evidence

Confirmed: image storage succeeds; the thumbnail workflow fails afterward, and the game thumbnail lists remain empty. The leading explanation is a Creator Dashboard/backend failure attaching the image to this experience. The specific backend reason is unconfirmed.

The next useful diagnostic is the failed upload/thumbnail request's HTTP status and response error message from a browser Network panel. Available automation exposes the page and console messages, but not network response bodies. Do not include session cookies, authorization headers, or a full HAR in a public report.
