@everywhere using Random: seed!



@testset "MPI Tests" begin

    pids = workers()
    println("MPI Test procs:$(pids)")
    seed!(0)
    seeds = rand(UInt,length(pids))
    n = 1
   
    
    @testset "Broadcast Test" begin
        
        @everywhere function broadcast_test_proc(n,communication)

            if communication.receiving_from === nothing 
                seed!(0)
                data = rand(Float64,n,n)
                broadcast(data,communication)
            else
                data = broadcast(nothing ,communication)
            end 

            if communication.receiving_from === nothing 
                broadcast(data,communication)
                profiled_data = data
            else
                profiled_data,_,_,_ = broadcast_profiled(nothing ,communication)
            end 

            return data, profiled_data      
        end
        

        bcast_pididx = 1
        #
        #  Stage the Communication
        #
        @inferred broadcast_communication(pids,bcast_pididx,zeros(Float64,0,0))
        communication = broadcast_communication(pids,bcast_pididx,zeros(Float64,0,0))

        futures = []

        #
        #  Start the processors
        #

        for p = 1:length(pids)
            future = @spawnat pids[p] broadcast_test_proc(communication[p],n)
        end

        bcast_vals = []
        bcast_profiled_vals = []

        
        # collect and aggregate the results 
        for future in futures
            bcast_data, bcast_profiled_data = fetch(future)
            push!(bcast_vals,bcast_data)
            push!(bcast_profiled_vals,bcast_profiled_data)
        end    

        @test all([v == bcast_vals[1] for v in bcast_vals])
        @test all([v == bcast_profiled_vals[1] for v in bcast_profiled_vals])

    end
 
    @testset "Gather Test" begin
    
        @everywhere function gather_proc_test(seed,n,communication)

            seed!(seed)
            my_data = rand(Float64,n,n)
            all_data = gather(my_data,communication)
            all_data_profiled,_,_,_ = gather_profiled(my_data,communication)

            return all_data, all_data_profiled
        
        end


        gather_pididx = 1
        
        #
        #  Stage the Communication
        #
        @inferred gather_communication(pids,gather_pididx,zeros(Float64,0,0))
        communication = gather_communication(pids,gather_pididx,zeros(Float64,0,0))

        futures = []


        #
        #  Start the processors
        #

        for p = 1:length(pids)
  
            future = @spawnat pids[p] gather_proc_test(seeds[p],n,communication[p])
            push!(futures,future)
        end


        gather_data, gather_profiled_data = fetch(futures[gather_pididx])

        serial_generated = []
        for seed in seeds
            seed!(seed)
            push!(serial_generated,rand(Float64,n,n))
        end

        @test serial_generated == gather_data
        @test serial_generated == gather_profiled_data

    end

    @testset "All to All Reduction" begin

        @inferred all_to_all_reduction_communication(pids,1)
        communication = all_to_all_reduction_communication(pids,1)
    

        @everywhere function all_to_all_reduction_proc(my_data,proc_communication)

            reduction_f = (x,y) -> x + y 
            reduced_data = all_to_all_reduce(reduction_f,my_data,proc_communication)

            return reduced_data       
        end


        test_vals = rand(1:100,length(pids))

        futures = []
    
        for p = 1:length(pids)
            future = @spawnat pids[p] all_to_all_reduction_proc(test_vals[p],communication[p])
            push!(futures,future)
        end

        all_vals = [] 
        for future in futures 
            push!(all_vals,fetch(future))
        end 

        @test sum(test_vals) == all_vals[1]
        @test all([v == all_vals[1] for v in all_vals])
        
    end
    

    @testset "Personalized All to All" begin

        @everywhere function personalized_all_to_all_proc(seed,n,comm)


            seed!(seed)

            all_data = Vector{Matrix{Float64}}(undef,length(comm.sending_to)+1)
            #data_for_me[comm.my_idx] = rand(Float64,n,n)
            for i = 1:length(comm.sending_to) + 1
                     # generate data for all_other_process
                all_data[i] = rand(Float64,n,n)
            end 

            #data_for_me = Vector{Matrix{Float64}}(undef,length(sending_to)+1)
                                            # expecting length(pids) - 1 data points  

            data_for_me = personalized_all_to_all(all_data,comm)
            data_for_me_profiled,_,_,_ = personalized_all_to_all_profiled(all_data,comm)
        
            return data_for_me, data_for_me_profiled
        
        end 
        

        for proc_batch in [pids,pids[1:4]]
            #  --  Stage the Communication  --  #
            @inferred personalized_all_to_all_communication(proc_batch,zeros(Float64,0,0))
            communication = personalized_all_to_all_communication(proc_batch,zeros(Float64,0,0))
            futures = []
        
        
            
            # -- Start the processors -- #
            for p = 1:length(proc_batch)
                future = @spawnat proc_batch[p] personalized_all_to_all_proc(seeds[p],n,communication[p])
                push!(futures,future)
            end
        

            all_vals = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            all_vals_profiled = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            

            # collect and aggregate the results 
            for (i,future) in enumerate(futures)
                data, data_profiled = fetch(future)
                all_vals[i,:] = data
                all_vals_profiled[i,:] = data_profiled
            end    
            
        
            serial_generated = Array{Matrix{Float64}}(undef,length(proc_batch),length(proc_batch))
            for p_i in 1:length(proc_batch)
                seed!(seeds[p_i])
                for p_j=1:length(proc_batch)
                    serial_generated[p_j,p_i] = rand(Float64,n,n)
                end
            end

            @test all_vals == serial_generated
            @test all_vals_profiled == serial_generated
    
        end
    end 

end