using OpenStreetMapX
using RSUOptimization
using Tables
using CSV
using DataFrames
#Creating MapData object
mapfile = "reno_east3.osm"
datapath = "C:/RSUOptimization.jl/example";
map_data = OpenStreetMapX.get_map_data(datapath, mapfile,use_cache=false; road_levels = Set(1:5));

#Defining starting and ending area
Start = ((39.50,-119.70),(39.55,-119.74))
End = ((39.50,-119.80),(39.55,-119.76))

#Proportion of smart agents
α = 1.0
N = 1000
density_factor = 5.0
range = 1000.0
throughput = 200
updt_period = 150
T = 5.0
k = 3
#Generating agents
Agents, init_times, init_dists = generate_agents(map_data, N, [Start], [End], α)
#Running base simulation - no V2I system
@time BaseOutput, tracking = base_simulation(map_data, Agents)
#ITS model with iterative RSU optimization
@time ITSOutput, RSUs = iterative_simulation_ITS(map_data, Agents, range, throughput, updt_period, debug_level=2)

RSUs = calculate_RSU_location(map_data, Agents, range, throughput)
@time ITSOutput, trackingITS = simulation_ITS(map_data,Agents,range,RSUs,150,T,k,density_factor,2)

typeof(trackingITS)
for i in 1:1000
  Agents[i].smart = true
end
println(tracking[295])
println(trackingITS[295])

map_data.w[389,390]
mean((BaseOutput.TravelTimes - ITSOutput.TravelTimes)./BaseOutput.TravelTimes)
(sum(BaseOutput.TravelTimes)-sum(ITSOutput.TravelTimes))/sum(BaseOutput.TravelTimes)
using StatsBase

"""
Smart cars percentage analysis
"""
ResultFrame = DataFrame(T = Float64[],
              TotalTimeReduction = Float64[],
              SmartTimeReduction = Float64[],
              NotSmartTimeReduction = Float64[],
              MinAvailability = Float64[],
              MeanRSUUtilization = Float64[],
              RSUs = Int[])

αs = 0.1:0.1:1
for element in αs
  for i=1:5
    println("$element : $i")
    #Generating agents
    Agents, init_times, init_dists = generate_agents(map_data, N, [Start], [End], element)
    #Running base simulation - no V2I system
    BaseOutput, tracking = base_simulation(map_data, Agents, debug_level = 0)
    #ITS model with iterative RSU optimization
    #ITSOutput, RSUs = iterative_simulation_ITS(map_data, Agents, range, throughput, updt_period, T = element, debug_level = 1)
    RSUs = calculate_RSU_location(map_data, Agents, range, throughput)
    ITSOutput, trackingITS = simulation_ITS(map_data,Agents,range,RSUs,updt_period,T,k,density_factor,1)
    step_statistics = gather_statistics(getfield.(Agents,:smart),
                                        BaseOutput.TravelTimes,
                                        ITSOutput.TravelTimes,
                                        ITSOutput.ServiceAvailability,
                                        ITSOutput.RSUsUtilization,
                                        RSUs)
    println(step_statistics)
    push!(ResultFrame, [element,
                        step_statistics.overall_time,
                        step_statistics.smart_time,
                        step_statistics.other_time,
                        step_statistics.service_availability,
                        step_statistics.RSUs_utilization,
                        step_statistics.RSU_count])
  end
end
CSV.write("results2.csv",ResultFrame)

speeds= OpenStreetMapX.get_velocities(map_data)
using LightGraphs
k_routes = LightGraphs.yen_k_shortest_paths(map_data.g, map_data.v[Agents[1].route[30]],
                                            map_data.v[Agents[1].end_node], map_data.w./speeds, k)
T=1.0
#Normalize k-paths travelling time
norm_time = k_routes.dists/maximum(k_routes.dists)
#Calculate probability of being picked for every route
exp_ntime = exp.(-norm_time/T)
probs = exp_ntime/sum(exp_ntime)
#Assign new route
new_path = sample([1,2,3], StatsBase.weights([1,2,3]))












using IJulia
notebook()
IJulia.installkernel("Julia nodeps", "--depwarn=no")


failedENU = ITSOutput.FailedUpdates
RSU_ENU = getfield.(RSUs,:ENU)

using PyCall
flm = pyimport("folium")
matplotlib_cm = pyimport("matplotlib.cm")
matplotlib_colors = pyimport("matplotlib.colors")

cmap = matplotlib_cm.get_cmap("prism")

m = flm.Map()
locs = [LLA(n, map_data.bounds) for n in RSU_ENU]
for k=1:length(RSU_ENU)

    info = "RSU number: $k"
    flm.Circle(
      location=[locs[k].lat,locs[k].lon],
      popup=info,
      tooltip=info,
      radius=range,
      color="blue",
      weight=0.5,
      fill=true,
      fill_color="blue"
   ).add_to(m)
        flm.Circle(
      location=[locs[k].lat,locs[k].lon],
      popup=info,
      tooltip=info,
      radius=1,
      color="crimson",
      weight=3,
      fill=false,
      fill_color="crimson"
   ).add_to(m)
end

routes = [a.route for a in Agents if a.smart]
#Paths
for z=1:length(routes)
    locs = [LLA(map_data.nodes[n],map_data.bounds) for n in routes[z]]
    info = "Agent $z route\n<BR>"*
        "Length: $(length(routes[z])) nodes\n<br>" *
        "From: $(routes[z][1]) $(round.((locs[1].lat, locs[1].lon),digits=4))\n<br>" *
        "To: $(routes[z][end]) $(round.((locs[end].lat, locs[end].lon),digits=4))"
    flm.PolyLine(
        [(loc.lat, loc.lon) for loc in locs ],
        popup=info,
        tooltip=info,
        weight = 2,
        color="green"
    ).add_to(m)
end

#failed transmissions
failedENU1 = unique(collect(Iterators.flatten(failedENU)))
flocs = [LLA(n, map_data.bounds) for n in failedENU1]
for i = 1:length(failedENU1)
    info = "Failed number: $i"
    flm.Circle(
      location=[flocs[i].lat,flocs[i].lon],
      popup=info,
      tooltip=info,
      radius=8,
      color="black",
      weight=3,
      fill=true,
        fill_color="black"
   ).add_to(m)
end

MAP_BOUNDS = [(map_data.bounds.min_y,map_data.bounds.min_x),(map_data.bounds.max_y,map_data.bounds.max_x)]
flm.Rectangle(MAP_BOUNDS, color="black",weight=6).add_to(m)
m.fit_bounds(MAP_BOUNDS)
m.save("RSUmap.html")
m
