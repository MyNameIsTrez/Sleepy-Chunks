The mod is a zip in `/home/trez/.var/app/com.valvesoftware.Steam/.factorio/mods/`.
Implement the ChatGPT conversation at `https://chatgpt.com/c/68ef9a36-d024-832d-9b11-f464e6813532`.

Here is the prompt I gave ChatGPT:
```
Here is my idea for a Factorio mod:
The tl;dr idea is that if you have a full iron ore belt going into an iron plate smelting chunk, and that smelting chunk outputs the iron plates to the steel smelting chunk next to it, then those chunks could go to sleep after 60 seconds of consistent input and output.

The steel smelting chunk can stay in a deep sleep, since its only neighbor chunk is the iron smelting chunk. The iron smelting chunk would be in a light sleep, since it'll have to keep checking whether the incoming iron ore rate hasn't dropped significantly. If it has changed significantly, it wakes up, and tells its neighboring steel smelting chunk to become the light sleeping chunk instead. So this is a chain reaction of factory-wide recalibration.

Edge cases like "what if there's a train/chest in the chunk" would be handled in the proof-of-concept by just never allowing those chunks to sleep.

The 60 sec recalibration could be lowered significantly of course with in-game settings, and the max active recalibrating chunks could also just be a setting, so that'd prevent sudden recalibration lag spikes.

Right now people talk about megabases in terms if millions of science per minute, but with this belt-focused optimization mod I am positive that billions of science per minute would run fine.

Deep sleeping chunks have no need for loaders, but light sleeping chunks put the incoming items into an invisible chest with an invisible loader, so the mod can check the item counts in the chest once every 60 seconds, and then clear the chest. The outgoing items are spawned using another invisible item loader and creative chest.

Both light and deep sleep meaning the chunk is inactive. Light sleeping chunks just additionally have loaders, since they act as the I/O chunks of your megafactory

And the mod only has to calculate stats for light sleeping chunks

I've coined the mod "Sleepy Chunks", and here are my empirical results:
- 16k factory chunks took 46 mspf (milliseconds per frame, where if it's higher than 16.6 mspf the game slows down).
- Destroying the 128k infinity chests didn't lower the mspf.
- Marking all entities as inactive brought the mspf down to 1.2.
- Destroying all entities brought the mspf down to 0.6.
- My conclusion is that destroying entities is overkill, so marking entities as inactive should be good enough for a first version of the mod.
```
