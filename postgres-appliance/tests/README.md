# Run tests

After building the image, you can test your image by:

1. Setting up the environment variable `SPILO_TEST_IMAGE` to test the specific image. If unset, the default will be `spilo`.
    ```
    export SPILO_TEST_IMAGE=<your_spilo_image>
    ```
2. Run the test:
    ```
    bash test_spilo.sh
    ```
    To enable debugging for an entire script when it runs:
    ```
    bash -x test_spilo.sh
    ```

The test will create multiple containers. They will be cleaned up by the last line before running `main` in `test_spilo.sh`. To keep and debug the containers after running the test, this part can be commented.
```
trap cleanup QUIT TERM EXIT
```

For the PostgreSQL 14–18 extension image, run `SPILO_TEST_IMAGE=<image> bash test_extensions.sh`.
This starts an isolated database for each installed major, checks the pinned server and extension
versions and packaged vector update paths, exercises HNSW, IVFFlat and Chinese
full-text indexing, checks that an ordinary role cannot write a server dictionary, and decodes
logical changes through pgoutput using the server's default output-plugin allowlist.
The test does not exercise upgrades of existing databases, Patroni replication or backup/restore of custom dictionaries.

Run `bash test_build_versions.sh` without Docker to check version argument validation.
For `test_extensions.sh`, build with an explicit `POSTGRESQL_VERSIONS` pin as shown
in the repository README. The CI fixture uses PG 18.6; release builds supply their
own exact version through the workflow input.
