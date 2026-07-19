module probe_diag
use xiom.vulkan;
use xiom.io;
use xiom.math;
fn main() -> Int {
  let app=create_app("P",800,600);
  match app {
    Ok(a)=>{
      var f=0;
      poll(a);
      let sc = should_close(a);
      io.println("should_close="+(if sc{"1"}else{"0"}));
      while f<60 && !should_close(a) {
        poll(a);
        let n1=now();let n2=now();let n3=now();
        set_clear_color(a,(math.sin(n1)*0.03+0.08)as Float32,(math.sin(n2+2.0)*0.03+0.08)as Float32,(math.sin(n3+4.0)*0.03+0.08)as Float32);
        let s=begin_frame(a);
        if s==1{draw_triangle_2d(a,(math.sin(n1)*0.5+0.5)as Float32,(math.sin(n2+2.0)*0.5+0.5)as Float32,(math.sin(n3+4.0)*0.5+0.5)as Float32);end_frame(a);f=f+1;}
        elif s==-1{io.println("ERR:"+last_error());break;}
      }
      io.println("frames="+(if f==60{"60"}else{"<60"}));
      if !should_close(a) { io.println("USER DID NOT CLOSE"); }
      destroy_app(a);
      return 0;
    }
    Err(e)=>{io.println(e);return 1;}
  }
}
