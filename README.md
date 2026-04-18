# airwave

## Project vision

### Phase 1
First phase I want some kind of visual for ADS-B data. Create a simple zig
program which ingests hackrf one samples, converts them if needed, and passes
to open source decoder, dump1090. Then store the dump1090 data on the disk, and
send it to any existing websocket client connections, maybe adjusting data
format so it's not straight dump1090 output, tbd.

Render a map with accurate dots of airplane locations and info. webpage.
Current plan is to vibe code some js web app, which needs to accept the ip
of the airwave server to register as a client and start receiving data.

### Phase 2
Move away from the web server and render natively. In software.

At the same time, starting learning how to control an e-ink display. Select
some decent e-ink display and drive it with some embedded soc (tbd), ideally a
cpu arch we can target with zig.

### Phase 3
Create client program for the phase 2 embedded device. Render overhead airplane
info on a wall mounted e-ink display. Like a smart picture frame for live
airplane data.

### Other goals
- Replace dump1090 with my own decoder. This was originally one of the main
  points to this project, though it's now more of a stretch goal. Getting
  things rolling with dump1090 so I can motivate myself with pixels moving on a
  display is the first task. Save the hard stuff for later after I know more
  about what's needed.
- Support distributed antenna nodes. Seems fun to work on syncing them and
  handling data aggregation. Probably run dump1090 on the node and send
  processed data over the wire.

## airwave server
simple program written in zig which configures and ingests data from a hackrf
one sdr. This airwave server must be able to store data on the disk and send
data (format tbd) to the front end web server.

- zig 0.16.0
- [dump1090](https://github.com/antirez/dump1090)

## Phase 1 Frontend
tbd I don't know much about web dev. I'm thinking some kind of webpage
with fancy vibe coded globe spinning (or local map?) with airplane info
overlaid. 

My first thought for the frontend backend communication is a websocket with the
airwave server pushing "events" / data to the clients.
