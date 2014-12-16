rampl.glob <- new.env()
.onLoad <- function(libname, pkgname) {
  init.rampl()  
}

#' @export
init.rampl = function() {
  rampl.glob$DISPLAY.LOG = NULL
}

#' @export
get.ampl.local.options = function() {
  list(
    "PATH" = c("option solver pathampl;","option presolve 0;")
  )
}

#' @export
get.ampl.neos.options = function() {
  list(
    "PATH" = c("option presolve 0;")
    # KNITRO OPTIONS FROM EXAMPLE OF CHE-LIN SU                         
    ,"KNITRO" = c("option knitro_options 'alg=1 outlev=3 opttol=1.0e-6 feastol=1.0e-6'")  
  )
}

#' Generates an AMPL data file
#' 
#' Generates a AMPL data file for the model specified in dat.file
#' sets and param are lists that contain the 
#' values of the sets and parameters that
#' are specified in the GMPL model
#' @param sets a list with the sets used by the gmpl model
#' @param param a list with the parameters used by the gmpl model
#' @param mod.file path of the .mod file in which the gmpl model is specified
#' @param dat.file path of the .dat file in which the data shall be written
#' @export
ampl.make.dat.file =  function(...) {
  gmpl.make.dat.file(...)
}

#' Returns a list of availble solver for AMPL on NEOS
#' @export
neos.ampl.solvers = function() {
  library(rneos)  
  txt = NlistAllSolvers(convert = TRUE, nc = CreateNeosComm())@ans
  dat = as.data.frame(fast_str_split_fixed(":",txt,3,fixed=TRUE))
  colnames(dat) = c("category","solver","inputMethod")
  dat = dat[dat[,"inputMethod"]=="AMPL" & dat[,1] != "kestrel",]
  ord = order(dat[,"solver"])
  cat = fast_str_split_fixed(":",NlistCategories()@ans,2,fixed=TRUE)
  
  cat.row = match(dat[,1],cat[,1])
  dat$descr = cat[cat.row,2]
  dat = dat[ord,]
  rownames(dat) = NULL
  dat
}
examples.neos.ampl.solvers = function() {
  neos.ampl.solvers()
}

#' Solves an AMPL model remotely using the NEOS Server
#' 
#' @param name the model name
#' @param category category of the optimization problem, call neos.ampl.solvers() for an overview
#' @param solver desired solver, call neos.ampl.solvers() for a list
#' @param path path in which mod.file, dat.file and run.file can be found
#' @param wait default=TRUE shall R wait until NEOS returns the solution (may take some time)
#' @export
ampl.run.neos = function(
  name="",category="cp", solver="PATH",path=getwd(), wait = TRUE,
  mod.file=paste(path,"/",name,".mod",sep=""),
  dat.file=paste(path,"/",name,".dat",sep=""),
  run.file=paste(path,"/",name,".run",sep=""),
  log.file = paste(path,"/log_",name,"_",solver,".txt",sep=""))
{
  restore.point("ampl.run.neos")
  
  library(rneos)

  display.start.log(log.file,append=FALSE)
  #NlistAllSolvers(convert = TRUE, nc = CreateNeosComm())
  
  ## import of file contents
  modc <- paste(paste(readLines(mod.file), collapse = "\n"), "\n")
  datc <- paste(paste(readLines(dat.file), collapse = "\n"), "\n")
  runc <- paste(paste(readLines(run.file), collapse = "\n"), "\n")

  #
  template <-NgetSolverTemplate(category = category, solvername = solver,inputMethod = "AMPL")
  ## create list object
  argslist <- list(model = modc, data = datc, commands = runc,comments = "")
  ## create XML string
  xmls <- CreateXmlString(neosxml = template, cdatalist = argslist)

  
  job <- NsubmitJob(xmlstring = xmls, user = "rneos", interface = "",id = 0)
  
  display(NprintQueue(convert = TRUE, nc = CreateNeosComm())@ans)
  #print(NgetJobInfo(obj = job, convert = TRUE))
  
  if (wait) {
    start.len = 1
    while(TRUE) {
      res = NgetIntermediateResults(obj = job, convert = TRUE)@ans
      res = strsplit(res,"\n",fixed=TRUE)[[1]]
      if (length(res)>=start.len) {
        display(res[start.len:length(res)])
      }
      start.len = length(res)+1;
      flush.console()
      Sys.sleep(0.1)
      
      #print(NgetJobInfo(obj = job, convert = TRUE))
      do.stop = NgetJobInfo(obj = job, convert = TRUE)@ans[4] == "Done"
      #print(NgetFinalResultsNonBlocking(job, convert = TRUE))
      if (do.stop) {
        break
      }
    }
    res = NgetFinalResults(obj = job, convert = TRUE)@ans
    res = strsplit(res,"\n",fixed=TRUE)[[1]]
    if (length(res)>=start.len) {
      display(res[start.len:length(res)])
    }
    #display(NgetIntermediateResults(obj = job, convert = TRUE)@ans) 
    
    display("Read solution...")
    dat = extract.all.var.from.AMPL.out(res)
    display("Solution has been read...")
    display.stop.log()
    
    return(dat)
  } else {
    display(NgetIntermediateResults(obj = job, convert = TRUE)@ans)
    # Print call 
    display("NgetIntermediateResults(obj = job, convert = TRUE)")
  }
  display.stop.log()
  return (job)
}

#' Generate a default run file for a given AMPL model
#' 
#' @param neos if true a run file for the neos server is created, otherwise for a local call to AMPL
#' @param path path in which mod.file, dat.file and run.file can be found
#' @export
ampl.make.run.file = function(name,run.name=name,options="",
                         var.out = NULL,neos=FALSE,path=getwd(), 
                         mod.file=paste(path,"/",name,".mod",sep=""),
                         run.file=paste(path,"/",run.name,".run",sep=""),
                         dat.file=paste(path,"/",run.name,".dat",sep="")) {
 restore.point("ampl.make.run.file")  
 str = paste(options,"\n\n",collapse="\n")
 if (!neos) {
   str = paste(str, "model \"", mod.file, "\";\n", "data \"",
               dat.file, "\";\n\n", sep = "")
 }
  str = paste(str,"solve;\n\n")
  
  mi = ampl.get.model.info(mod.file)
  if (is.null(var.out)) {
    var.out = mi$var
  }
  
  
  var.sets.str= sapply(mi$var.sets[var.out], function(sets) {
    if (is.na(sets[1]))
      return('""')
    paste('"',sets,'"',collapse=",",sep="")
  })
  var.str = paste(
    'print "#!STARTOUT:', var.out, '";\n',
    'print ', var.sets.str,';\n',
    "display ",var.out,";\n",
    'print "#!ENDOUT:', var.out, '";\n',
    collapse="\n",sep="")
  str = paste(str,
"
option display_1col 10000000;
option display_width 1000;
",              
              var.str)
  
  writeLines(str,run.file)
}  

extract.all.var.from.AMPL.out = function(str) {
  restore.point("extract.all.var.from.AMPL.out")
  
  start.ind = which(str_sub(str,start=0,end=11)=="#!STARTOUT:")
  end.ind   = which(str_sub(str,start=0,end=9)=="#!ENDOUT:")
  var.names = str_sub(str[start.ind],start=12)

  if (length(var.names)>0) {
    ret=lapply(1:length(var.names),
               function(i) {
                 txt = str[(start.ind[i]+1):(end.ind[i]-1)]
                 extract.var.from.AMPL.out(txt)
               })
    names(ret)=var.names
  } else {
    ret = list()
  }
  return(ret)
}


extract.var.from.AMPL.out = function(str) {
  restore.point("extract.var.from.AMPL.out")
  sets = str_trim(str[1])
  str = str[-1]
  is.scalar = sets == ""
  
  if (is.scalar) {
    val = as.numeric(str_trim(str_split_fixed(str[1],"=",n=2)[1,2]))
  } else {
    # replace spaces by just one space
    str = str_trim(str_replace_all(str,"( )+"," "))  
    end = grep(";",str,fixed=TRUE)-1
    str = str[2:end]
    ncol = NROW(str_locate_all(str[1],fixed(" "))[[1]])+1
    mat = fast_str_split_fixed(" ",str,ncol=ncol,fixed=TRUE)    
    #print(ncol)
    if (ncol==2) {
      val = as.numeric(mat[,ncol])
      names(val) = mat[,1] 
    } else if (ncol==3) {
      restore.point("my.restore")
      rn = unique(mat[,1])
      cn = unique(mat[,2])
      nr = length(rn)
      nc = length(cn)
      val = matrix(as.numeric(mat[,ncol]),nr,nc,byrow=TRUE)
      rownames(val) = rn
      colnames(val) = cn
    } else {
      val = as.data.frame(mat)
      val[,ncol] = as.numeric(val[,ncol])
      colnames(val) = c(str_split(sets, fixed(" ")),"val")
    }
  }
  return(val)
}


#' Solves an AMPL model using a local installation of AMPL
#' 
#' You need to have a local AMPL installation with the corresponding solvers. It is assumed that a call to ampl finds the executable file, i.e. in Windows you have to add the AMPL directory to the system PATH variable
#' @export
ampl.run.local = function(name="",path=getwd(), run.file=paste(path,"/",name,".run",sep=""), display=TRUE) {
  restore.point("ampl.run.local")
  
  command = paste("ampl",' "',run.file,'"',sep="") 
  
  ret = system(command,intern = TRUE,wait=TRUE,ignore.stdout = FALSE, ignore.stderr = FALSE, show.output.on.console=TRUE, invisible=FALSE)
  
  if (display)
    display(ret)
  extract.all.var.from.AMPL.out(ret)
}


examples.ampl.run.local = function() {
  # Model of power plant investments and dispatch included in package
  mod.file = paste(.path.package(package = "rampl"),"/data/cournot.mod",sep="")
  dat.file = paste(.path.package(package = "rampl"),"/data/cournot.dat",sep="")
  run.file = paste(getwd(),"/cournot.run",sep="")
  
  ampl.make.run.file(name="cournot", options=c("option solver minos;"), mod.file=mod.file,dat.file=dat.file,run.file=run.file)
  ret = ampl.run.local(name="cournot", display=TRUE, run.file=run.file)
  ret
  
  # Solve for different parameter values
  n = 2
  sets = list(N=1:n)
  param = list(a=1,b=1,c=c(0.1,0.1))
  
  dat.file = paste(getwd(),"/cournot.dat",sep="")
  run.file = paste(getwd(),"/cournot.run",sep="")
  ampl.make.run.file(name="cournot", options=c("option solver minos;"), mod.file=mod.file,dat.file=dat.file,run.file=run.file)
  
  solve.cournot = function(c1=0,c2=0) {
    param$c = c(c1,c2)
    ampl.make.dat.file(mod.file=mod.file,dat.file=dat.file,sets = sets, param=param)
    ret = ampl.run.local(name="cournot", display=FALSE, run.file=run.file)
    t(ret$q)
  }
  solve.cournot(c1=0.1,c2=0)
  library(sktools)
  ret = run.scenarios(solve.cournot, par=list(c1=seq(0,1,length=10),c2=0))
  colnames(ret)=c("scen.id","c1","c2","q1","q2")
  ret
}


examples.ampl.run.neos = function() {
  # Model of power plant investments and dispatch included in package
  mod.file = paste(.path.package(package = "rampl"),"/data/cournot.mod",sep="")
  dat.file = paste(.path.package(package = "rampl"),"/data/cournot.dat",sep="")
  run.file = paste(getwd(),"/cournot.run",sep="")
  ampl.make.run.file(name="cournot", neos=TRUE, mod.file=mod.file,dat.file=dat.file,run.file=run.file, options=c(""))
  ret = ampl.run.neos(name="cournot", category="nco", solver="MINOS", mod.file=mod.file, dat.file=dat.file, run.file=run.file)
  ret
  
  # Solve for different parameter values
  n = 2
  sets = list(N=1:n)
  param = list(a=1,b=1,c=c(0.1,0.1))
  
  dat.file = paste(getwd(),"/cournot.dat",sep="")
  run.file = paste(getwd(),"/cournot.run",sep="")
   
  solve.cournot = function(c1=0,c2=0, neos=FALSE) {
    param$c = c(c1,c2)
    ampl.make.dat.file(mod.file=mod.file,dat.file=dat.file,sets = sets, param=param)

    if (!neos) {
      
       ampl.make.run.file(name="cournot", options=c("option solver minos;"), mod.file=mod.file,dat.file=dat.file,run.file=run.file)
      ret = ampl.run.local(name="cournot", display=FALSE, run.file=run.file)
    
    } else {
      ampl.make.run.file(name="cournot", neos=TRUE, mod.file=mod.file,dat.file=dat.file,run.file=run.file, options=c(""))
      ret = ampl.run.neos(name="cournot", category="nco", solver="MINOS", mod.file=mod.file, dat.file=dat.file, run.file=run.file)
    }
    t(ret$q)
  }
  solve.cournot(c1=0.1,c2=0, neos=TRUE)
  
}


display.start.log = function(log.file,append=FALSE) {
  if (append) {
    rampl.glob$DISPLAY.LOG = file(log.file,open="at")
  } else {
    rampl.glob$DISPLAY.LOG = file(log.file,open="wt")
  }
}
display.stop.log = function() {
  rampl.glob$DISPLAY.LOG = NULL
}

# Display stuff in a convenient form
display = function(...,collapse="\n",sep="") {
  str = paste("\n",paste(...,collapse=collapse,sep=sep),"\n",sep="")
  if (!is.null(rampl.glob$DISPLAY.LOG)) {
    write(str,rampl.glob$DISPLAY.LOG,append=TRUE)
  }
  invisible(cat(str))
  #print(str,quote=FALSE)
}

#' Quickly splits strings by a fixed pattern
#' @export
fast_str_split_fixed = function(pattern,text,ncol=NULL,...) {
  restore.point("fast_str_split_fixed")
  if (NROW(text)==0) {
    return(NULL)
  }
  if (is.null(ncol)) {
    ncol = length(gregexpr(pattern,text[1],...)[1])+1
  }
  if (ncol==1)
    return(text)
  library(data.table)
  mat = as.data.table(matrix(NA,length(text),ncol))
  for (i in 1:(ncol-1)) {
    #right.pos  = regexpr(pattern,text,...)
    right.pos  = regexpr(pattern,text,fixed=TRUE)
    mat[,i:=substring(text,1,right.pos-1), with=FALSE]
    text = substring(text,right.pos + attr(right.pos,"match.length"))
  }
  mat[,ncol:=text, with=FALSE]
  return(as.matrix(mat))
}

#' Adapted from gmpl get.model.info
ampl.get.model.info <- function (mod.file) 
{
  restore.point("ampl.get.model.info")
  require(stringr)
  str = readLines(mod.file)
  str = str_trim(str)
  rows = str_sub(str, 1, 3) == "set"
  txt = str_trim(str_sub(str[rows], 4))
  end.name = str_locate(txt, "[{;=<> ]")[, 1]
  sets.name = str_sub(txt, 1, end.name - 1)
  extract.sets = function(txt) {
      brace.start = str_locate(txt, fixed("{"))[, 1]
      brace.end = str_locate(txt, fixed("}"))[, 1]
      in.brace = str_sub(txt, brace.start + 1, brace.end - 
          1)
      my.sets = str_split(in.brace, fixed(","))
      my.sets = lapply(my.sets, str_trim)
      my.sets = lapply(my.sets, function(set) {
          if (is.na(set[1])) 
              return(set)
          set = str_trim(set)
          in.pos = str_locate(set, fixed(" in "))[, 2]
          rows = which(!is.na(in.pos))
          if (length(rows) > 0) 
              set[rows] = substring(set[rows], in.pos[rows] + 
                1)
          return(set)
      })
      return(my.sets)
  }
  sets.sets = extract.sets(txt)
  names(sets.sets) = sets.name
  
  rows = str_sub(str, 1, 3) == "var"
  txt = str_trim(str_sub(str[rows], 4))
  end.name = str_locate(txt, "[{;=<> ]")[, 1]
  var.name = str_sub(txt, 1, end.name - 1)
  var.sets = extract.sets(ampl.str.left.of(txt,"="))
  names(var.sets) = var.name
  
  
  rows = str_sub(str, 1, 5) == "param"
  txt = str_trim(str_sub(str[rows], 6))
  end.name = str_locate(txt, "[{;=<> ]")[, 1]
  param.name = str_sub(txt, 1, end.name - 1)
  param.sets = extract.sets(txt)
  names(param.sets) = param.name
  comment.start = str_locate(txt, fixed("#"))[, 1]
  comment.start[is.na(comment.start)] = 1e+06
  param.defined = str_detect(substring(txt, 1, comment.start), 
      fixed("="))
  return(list(sets = sets.name, sets.sets = sets.sets, var = var.name, 
      var.sets = var.sets, param = param.name, param.sets = param.sets, 
      param.defined = param.defined))
}


ampl.str.left.of <-function (str, pattern, ..., not.found = str) 
{
    pos = str_locate(str, fixed(pattern))
    res = substring(str, 1, pos[, 1] - 1)
    rows = is.na(pos[, 1])
    res[rows] = not.found[rows]
    res
}