# Fixture kontrak

Contoh request/response asli, dibaca dua sisi:

- vitest (`apps/backend/test`): respons server harus cocok.
- test Dart (`apps/mobile/test/data/backend_client_test.dart`, helper `contract()`): client harus bisa parse.

Format: `{ "request": { "method", "path", "headers"? , "body"? }, "response": { "status", "headers"?, "body" } }`.
Field dinamis (mis. `requestId`) tidak dimasukkan.

Placeholder `<token>`, `<id>`, `<iso>` = nilai dinamis: test cuma cek tipe/bentuknya (string tidak kosong, ISO 8601), bukan isinya.
