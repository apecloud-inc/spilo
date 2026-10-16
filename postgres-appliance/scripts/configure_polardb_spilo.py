#!/usr/bin/env python3

"""Apply PolarDB-PG-safe defaults around the stock Spilo configurator."""

import os
import subprocess
import sys

import yaml


BASE_CONFIGURATOR = "/scripts/configure_spilo_base.py"
PATRONI_CONFIG = os.path.join(os.environ.get("RW_DIR", "/run"), "postgres.yml")
POLAR_PARAMETERS = {
    "polar_worker.enable_standby_wal_prealloc": "off",
    "polar_resource_manager.enable_resource_manager": "off",
}


def configure_environment() -> None:
    """Prevent Spilo from appending PGDG-only preload libraries by default."""

    variable = "SPILO_CONFIGURATION" if "SPILO_CONFIGURATION" in os.environ else "PATRONI_CONFIGURATION"
    raw_config = os.environ.get(variable, "")
    config = yaml.safe_load(raw_config) or {}
    if not isinstance(config, dict):
        # Preserve the stock configurator's validation and error message.
        return

    parameters = config.setdefault("postgresql", {}).setdefault("parameters", {})
    parameters.setdefault("shared_preload_libraries", "")
    os.environ[variable] = yaml.safe_dump(config)


def has_compatibility_mode(initdb_options: list) -> bool:
    for option in initdb_options:
        if isinstance(option, dict) and (
            "compatibility_mode" in option or "compatibility-mode" in option
        ):
            return True
        if option in ("-m", "--compatibility-mode", "--compatibility_mode"):
            return True
    return False


def apply_polardb_defaults() -> None:
    compatibility_mode = os.environ.get("POLARDB_COMPATIBILITY_MODE", "pg").lower()
    if compatibility_mode not in ("pg", "ora"):
        raise ValueError("POLARDB_COMPATIBILITY_MODE must be pg or ora")
    pg16 = os.environ.get("PGVERSION") == "16"
    if pg16 and compatibility_mode != "pg":
        raise ValueError("PolarDB-PG 16 RPM only supports pg compatibility mode")

    with open(PATRONI_CONFIG, encoding="utf-8") as stream:
        config = yaml.safe_load(stream)

    local_parameters = config.setdefault("postgresql", {}).setdefault("parameters", {})
    dcs_parameters = (
        config.setdefault("bootstrap", {})
        .setdefault("dcs", {})
        .setdefault("postgresql", {})
        .setdefault("parameters", {})
    )
    for name, value in POLAR_PARAMETERS.items():
        if pg16 and name == "polar_worker.enable_standby_wal_prealloc":
            continue
        dcs_parameters.setdefault(name, value)
    local_parameters.setdefault("shared_preload_libraries", "")
    dcs_parameters.setdefault("shared_preload_libraries", "")

    initdb_options = config["bootstrap"].setdefault("initdb", [])
    if not isinstance(initdb_options, list):
        raise ValueError("bootstrap.initdb must be a list")
    if pg16:
        for option in initdb_options[:]:
            if isinstance(option, dict) and ("compatibility_mode" in option or "compatibility-mode" in option):
                mode = option.get("compatibility_mode", option.get("compatibility-mode"))
                if mode != "pg":
                    raise ValueError("PolarDB-PG 16 RPM only supports pg compatibility mode")
                initdb_options.remove(option)
    elif not has_compatibility_mode(initdb_options):
        initdb_options.append({"compatibility_mode": compatibility_mode})

    with open(PATRONI_CONFIG, "w", encoding="utf-8") as stream:
        yaml.safe_dump(config, stream, default_flow_style=False, width=120, sort_keys=False)


def main() -> int:
    configure_environment()
    result = subprocess.run([sys.executable, BASE_CONFIGURATOR, *sys.argv[1:]], check=False)
    # Stock configure_spilo deliberately returns 1 when WAL-G is disabled; the
    # Patroni file is still complete and launch.sh uses the status only to skip
    # the backup helper.
    requested_components = set(sys.argv[1:])
    if requested_components.intersection({"all", "patroni"}) and os.path.exists(
        PATRONI_CONFIG
    ):
        apply_polardb_defaults()
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
