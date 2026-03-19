# Knyle Share

I want a web app that allows me to  quickly share things from my computer on the internet.

The service will live at https://share.warpspire.com and each bundle I share will be available under a sub-directory of this domain.

I want this to be a rails-based application. I will be hosting this service on my Render account.

## Authentication

For each of these bundles, I want the ability to optionally enable authentication so it is not publicly available on the internet. I want to be able to authenticate it two ways:

- A text password I can share with people
- A URL parameter that has a customizable timed expiration

## Admin Section

I want this service to have an admin section that only I will be using. It will list bundles and allow me to enable/disable them or delete them.

I also want this admin screen to have some simple analytics for each of these bundles. Mostly I want to see if anyone (other than me) has viewed a bundle and how many unique people have viewed password protected bundles.

## Command Line Interface

I want a CLI that I can install on my machine to upload bundles. I also want to write an LLM Skill that will use this CLI.

I want to be able to `cd` into a directory and type in `knyle-share .` to start the process.

I want to write the skill so I can say "Share this bundle" inside of a Claude Code or Codex session. It should also allow me to say things like "Share the `app` folder as a bundle"

Both the command line and the skill should verify the bundle name before sharing, and confirm if it should be password protected. 

When it is password protected, it should offer a randomly generated password and confirm with me that is what it should use. The password should be simple and human memorable. Something people can write on a post-it, or remember if I say it over the phone.

## Example Use Cases

## Poke Website

I have a static website called `poke-recipes` on my computer in a folder. I would upload this static website to Knyle Share through an command line client on my computer to the Knyle Share API. I would set a password of `pokerocks` for viewing this static website.

- The website would be available at https://share.warpspire.com/poke-recipes
- For unauthenticated users, a password screen would render
- When they type in the password `pokerocks` they would be able to view the website for 24 hours

## Landscaping Blueprints Zip

I have a zip file called `Blueprints.zip` that includes blueprints for a landscaping project that I want to share with my contractor. I would upload this zip file using the command line interface.

- Since this is a zip file, the command line interface would ask me what the bundle name should be. I would type in `landscaping-project`
- The website would be available at https://share.warpspire.com/landscaping-project
- Since this is a single file, the service would render an HTML page with a large button to download the zip file.

## Blog Post Draft

I have a long markdown file of a blog post I'm working on called `Summer in the Sierra.md` and want to share it with a friend for review. I would upload this markdown file using the command line interface.

- Since this is a markdown file and can be rendered, the service would create a rendered view of the document using a standard CSS file.
- On the rendered file there would also be the option to download the markdown file or view the raw source.