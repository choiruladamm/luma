# Fixture kontrak

Contoh request/response asli, dibaca dua sisi:

- vitest: `packages/contracts/test` mem-parse tiap fixture dengan skemanya, dan test `apps/backend/test` mencocokkan respons server.
- test Dart (`apps/mobile/test/data/backend_client_test.dart`, helper `contract()`): client harus bisa parse.

Format: `{ "request": { "method", "path", "headers"? , "body"? }, "response": { "status", "headers"?, "body" } }`.
Field dinamis (mis. `requestId`) tidak dimasukkan.

Placeholder `<token>`, `<id>`, `<iso>` = nilai dinamis: test cuma cek tipe/bentuknya (string tidak kosong, ISO 8601), bukan isinya.
