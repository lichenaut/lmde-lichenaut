# lmde_lichenaut

## Running the script

In your terminal, navigate to the directory that contains `lmde_lichenaut.sh` and execute the following commands:

```bash
chmod +x lmde_lichenaut.sh
./lmde_lichenat.sh
```

The script will bring up this menu for you to choose an option:

```
LMDE ISO download: https://www.linuxmint.com/download_lmde.php
Script modes:

    1) Format drive from ISO
    2) Installation - Personalize computer, thorough updating
    3) Update - Streamlined updating

Which do you want to run (0 to abort)? [0-3]:
```

As the script finishes running, it will ask you if you want to reboot, and waits 10 seconds before exiting itself without rebooting.

## Prompting

If you choose the \_ option, you will be immediately prompted about:

- **Format**: the locations of your ISO file and drive.
- **Installation**: prior setup completion.
- **Update**: N/A

## Installation and Update options

You are intended to use the **Installation** option first, and then the **Update** option afterwards indefinitely.

Using the **Installation** option afterwards is possible, and does update more than the **Update** option, but is oftentimes redundant.
