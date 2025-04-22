# fi — The Commandline Company

```shell
$ fi -h
 Usage: fi [command] [options]

 Commands:
  init            Initialize fi
  git             Configure git remotes, push, pull, status
  client          Manage clients
  rate            Manage rates
  letter          Manager letters
  offer           Manager offers
  invoice         Manage invoices
  serve           Start the HTTP server for a web UI

 General Options:
  -h, --help      Displays this help message then exits

  -C, --fi_home   The FI_HOME dir to use
                  Default: $FI_HOME orelse ~/.fi
```



`fi` is what I use to create offers, invoices, and the occasional letter for my
own company. It helps manage business documents using LaTeX and Git in a
structured, auditable way.

The default LaTeX templates are laid out according to conventions common in the
German-speaking world.

`fi` sets up a Git-managed directory structure (“fi home”) and guides you through
each step of the document lifecycle. You define your company details — including
name, address, bank info, contact email, and logo — once in a JSON config file.
Clients and rate sets are added through their own editable JSON records.

When you create a new document, `fi` generates a self-contained working
directory containing the LaTeX template, your logo, and metadata placeholders. A
JSON file is also created and pre-filled with client information and other
defaults. You edit that file to customize document-specific fields — such as the
project name, applicable rates, VAT settings, or footer options. For offers and
invoices, you also fill in a `billables.csv` with the actual billable items.

Once the details are in place, you use `fi compile` to render the PDF. When
you’re satisfied, `fi commit` assigns a permanent ID, re-renders the PDF, and
commits the entire directory to the Git-managed archive.

---

## Features

- Company-wide configuration of name, address, bank info, and logo
- Structured client and rate set definitions
- Generates working directories with LaTeX files, logo, and metadata
- CSV-based input for billables (invoices/offers)
- Manual editing and iterative compilation
- Reliable ID assignment with file locking
- Git-managed document archive ("fi home")

---

## Getting Started

### 1. Initialize your company setup

```sh
fi init --generate=true config.json
# edit config.json to set company details
fi init config.json

# (optional) configure a remote to sync your document archive
fi git remote add --repo=online --url=user@server.com:fi_archive.git
```

---

### 2. Add a client and rate set

```sh
fi client new acme
# edit acme.json with client address and contact info
fi client commit acme

fi rate new standard
# edit standard.json with named entries and amounts
fi rate commit standard
```

---

### 3. Create and finalize a document

```sh
fi invoice new acme --rates=standard
cd invoice--2025-XXX--acme/

# edit billables.csv and invoice.json
fi invoice compile
#          ^^^ repeat editing and compiling until satisfied

fi invoice commit

# (optional) push the updated archive to your remote
fi git push    # [--repo=online]
```

- `compile` generates a PDF using LaTeX (run twice for references)
- `commit` assigns an ID, recompiles, and archives the result to `fi home`, then commits it to Git

---

## Document Types

| Type     | Inputs                            | Uses CSV? | Notes                      |
|----------|-----------------------------------|-----------|----------------------------|
| Offer    | JSON metadata, billables.csv      | Yes       | Project title, rates etc.  |
| Invoice  | JSON metadata, billables.csv      | Yes       | Totals, VAT, etc.          |
| Letter   | JSON metadata, direct LaTeX edit  | No        | Freeform content           |

Each type generates a directory like `offer--2025-XXX--clientname/`. Temporary IDs (`XXX`) become permanent on commit.

---

## Philosophy

`fi` is minimal and transparent. It helps generate documents with consistent
structure and layout, but leaves all meaningful content — text, metadata, layout
— under your direct control.

Everything is local, version-controlled, and reproducible. You can sync your
archive using fi git push, or host it behind SSH on a hardened server. Since
everything is file-based, fi works just as well remotely or in air-gapped
environments.

---

## License

[MIT](./LICENSE)
