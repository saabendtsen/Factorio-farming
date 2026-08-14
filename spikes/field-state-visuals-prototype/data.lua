local cultivated = table.deepcopy(data.raw.tile["lab-dark-1"])
cultivated.name = "ff-spike-cultivated"
cultivated.order = "z[ff-spike-cultivated]"
cultivated.minable = nil
cultivated.map_color = {r = 0.31, g = 0.20, b = 0.08}

data:extend {cultivated}
