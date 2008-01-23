require"luarocks.require"
require"cosmo"
cosmo2=require"template.cosmo"



template = "$do_cards[[$rank of $suit, ]]"
mycards = { {"Ace", "Spades"}, {"Queen", "Diamonds"}, {"10", "Hearts"} }
values = {
           do_cards = function()
              for i,v in ipairs(mycards) do
                 cosmo.yield{rank=v[1], suit=v[2]}
              end
           end
         }

-- Original Cosmo, reused template
start = os.clock()
fill = cosmo.f(template)
for i=1,100000 do
   result = fill(values)
end
print("Original Cosmo, reused template: "..tostring(os.clock()-start))

-- Original Cosmo, reused template
start = os.clock()
for i=1,100000 do
   result = cosmo.fill(template..tostring(i), values)
end
print("Original Cosmo, different templates: "..tostring(os.clock()-start))

-- LPEG Cosmo, reused template
start = os.clock()
fill = cosmo2.f(template)
for i=1,100000 do
   result = fill(values)
end
print("LPEG Cosmo, reused template: "..tostring(os.clock()-start))

-- LPEG Cosmo, different templates
start = os.clock()
for i=1,10000 do -- run only 10000 times, then multiply the time
   result = cosmo2.fill(template..tostring(i), values)
end
print("LPEG Cosmo, different template: "..tostring((os.clock()-start)*10))


