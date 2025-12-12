---
title: "Building Zig binaries with Docker"
date: 2025-12-13
---

# Building Zig binaries with Docker

I've recently decided to learn Zig. It's a nice language, and learning something new is always useful.
I also believe that the best way to learn something is by doing, so I've built a [Sleep-As-A-Service](https://github.com/keddad/saas) - a nice and simple webservice.

A thing with webservices is that you usually build and run those inside Docker. It's usually not a problem, something simple like `FROM golang:1.25 AS builder` should suffice.
So, naturally, I googled "Zig docker". It turns out that Zig project makes claims that [Zig makes Docker irrelevant](https://github.com/ziglang/docker-zig), and asking about that on its subreddit
leads to a lot of people [claiming](https://www.reddit.com/r/Zig/comments/1hjvyyd/zig_docker_image_rant/) you are doing something wrong if you are building Zig inside containers.

This claim has some merits: Zig has a great toolchain which should allow for easy (cross)compiling without the need for much tooling installed. However, it often just makes sense to build your stuff in Docker, even if you could do it without it. So, let's write a build container for Zig from scratch.

## Sensible approach

`zig` is a popular tool, and it's packaged with many distributions. Since we are writing a Dockerfile, let's just grab a fresh Alpine image and use that as a builder.
Something like this should work:

```dockerfile
FROM alpine:3.22.2 AS build

RUN apk add zig

# ...copy sources...

RUN zig build
```

Great, that's all. It can build your code. All those Zig fans were right, no image necessary. However, if it were the case, we wouldn't be here, would we?

## Not so sensible approach

For some cases, it works just fine. However, Zig is still not stable (at the time of writing, the most recent version is `0.15.2`, which doesn't sound stable at all).
That means that you might need a specific compiler version for your project. And that specific version might not be available in your distro's repositories, either because it's too old, or it's too fresh.
In fact, that's what happened to me: a library I was using was developed against the most recent Zig version, but the latest available at stable Apline repository was `0.14.0`.

Well, that sucks. But surely, we can just download the binary directly from Zig's website? To their credit, their compiler is pretty much stand-alone: you only need `zig` binary and some libraries distributed with it to compile code. Let's try doing this:
```dockerfile
FROM alpine:3.22.2 AS build

RUN apk add tar xz

RUN wget https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz -O zig.tar.xz

RUN tar -xf zig.tar.xz

RUN mkdir -p /opt/zig/

RUN cp -r zig-x86_64-0.15.2/* /opt/zig/

# ...copy sources...

RUN /opt/zig/zig build
```

That *should* work. Except that now we are hardcoding arch and zig version in a couple of places. Also, Zig asks us to identify ourselves when downloading stuff. So we'll add some ENVs - not great, not terrible. That should be all, right? **Wrong.** It turns out that Zig's website is ["intentionally hosted on a simple one-computer configuration"](https://ziglang.org/download/community-mirrors/), and no guarantees whatsoever are provided. Instead, we should be downloading our stuff from a set of community mirrors. However, their list is fetched from ziglang.org, so that won't help you when it will go down.
Fine, let's use those instead. Should be simple:

```dockerfile
RUN wget https://ziglang.org/download/community-mirrors.txt

RUN wget $(shuf -n 1 ./community-mirrors.txt)/zig-${HOST}-${ZIG_VERSION}.tar.xz?source=${PROJECT} -O zig.tar.xz
```

Except it's not. It turns out that downloading random binaries from the internet and executing them is a bad idea. To mitigate that, you should also download a release signature, 
and verify it against Zig's public key. So now you also have to install minisign, grab the signature itself and do some checks:

```dockerfile

RUN apk add minisign

RUN wget $(shuf -n 1 ./community-mirrors.txt)/zig-${HOST}-${ZIG_VERSION}.tar.xz.minisig?source=${PROJECT} -O zig.tar.xz.minisig

RUN minisign -Vm zig.tar.xz -x zig.tar.xz.minisig -P RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U
```

And with that, you should have a way to get whatever version of Zig you need into your container. 
Except those mirrors go down time to time, so you have to bake in some retries - that shall be left as an exercise to the reader.

## Working Dockerfile

In the end, your Dockerfile might look something like this:

```dockerfile
FROM alpine:3.22.2 AS build

# Find those at https://ziglang.org/download/
ENV HOST=x86_64-linux
ENV ZIG_VERSION=0.15.2

# Used to identify downloader, set to something recognizable
ENV PROJECT=my-amazing-pigeon-whatever

RUN apk add tar xz minisign

RUN wget https://ziglang.org/download/community-mirrors.txt

RUN wget $(shuf -n 1 ./community-mirrors.txt)/zig-${HOST}-${ZIG_VERSION}.tar.xz?source=${PROJECT} -O zig.tar.xz
RUN wget $(shuf -n 1 ./community-mirrors.txt)/zig-${HOST}-${ZIG_VERSION}.tar.xz.minisig?source=${PROJECT} -O zig.tar.xz.minisig

# Public key from https://ziglang.org/download/
RUN minisign -Vm zig.tar.xz -x zig.tar.xz.minisig -P RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U

RUN tar -xf zig.tar.xz

RUN mkdir -p /opt/zig/

RUN cp -r zig-${HOST}-${ZIG_VERSION}/* /opt/zig/

RUN mkdir -p ~/build

WORKDIR /root/build

COPY build.zig build.zig.zon /root/build/

COPY src/ /root/build/src/

RUN /opt/zig/zig build -Doptimize=ReleaseSmall
```

And with the exception of bad mirrors, it will work fine. Except it is a hell of a lot harder then just running `FROM zig:0.15.2 AS builder` for no good reason.
Moreover, normal people probably aren't doing all that. They will just grab an archive link from Zig's website and bake it into their CI - no ENVs, no mirrors, no signature checking.
Secure, clean and robust solutions should be the easiest ones to adapt. Rejecting established tools in the name of ideological purity only leads to people rolling out their own half-baked crutches.

If you faced the same problem - just use the example above, it should work fine for your needs. If you are someone from Zig Software Foundation, make the world (and your language developer experience) a better place and publish some official Docker images - you will make some people happier, and their CI more secure and robust.