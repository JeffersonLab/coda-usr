/*************************************************************************
 *
 *  vtp_list.c -      Library of routines for readout of events using a
 *                    JLAB Trigger Interface V3 (TI) with a VTP in
 *                    CODA 3.0.
 *
 *                    This is for a VTP with serial connection to a TI
 *
 */

/* Event Buffer definitions */
#define MAX_EVENT_LENGTH 40960
#define MAX_EVENT_POOL   100

#define STREAMING_MODE

#include <VTP_source.h>
#include "userCommand.c"

#undef USE_DMA
#undef READOUT_TI
#undef READOUT_VTP

#define NUM_VTP_CONNECTIONS 1   /* Can be up to 4 UDP or 2 TCP connections */
#define VTP_NET_MODE        1   /*  0=TCP 1=UDP   */
#define ENABLE_EJFAT        1   /* Enable EJFAT Headers - only valid for UDP transport */
#define DISABLE_CMSG_HDR    1   /* Disable sending cMsg headers with the data */ 

/* define an array of Payload port Config Structures */
PP_CONF ppInfo[16];

/* Data necessary to connect via TCP using EMUSockets
#define CMSG_MAGIC_INT1 0x634d7367
#define CMSG_MAGIC_INT2 0x20697320
#define CMSG_MAGIC_INT3 0x636f6f6c
There are 5 additonal words defined
- cMsg Version number: currently 6
- CODA ID for the ROC: set to 0 here but will be updated correctly later
- Max buffer size being sent:  4196352 bytes
- Total number of Sockets being created:  This is for EmuSockets Fat pipes only
- ID of the socket: starting at 1 (set to 0 here - will be updated later)
*/
unsigned int emuData[] = {0x634d7367,0x20697320,0x636f6f6c,6,0,4196352,NUM_VTP_CONNECTIONS,0};


/**
                        DOWNLOAD
**/
void
rocDownload()
{
  int stat;
  char buf[1000];
  /* Streaming Version 3 firmware files for VTP */
  //  const char *z7file="fe_vtp_z7_streamingv3_ejfat_v5.bin"; /* EJFAT support */
  //const char *z7file="fe_vtp_z7_streamingv3_ejfat_v5_July10_2026.bin"; /* EJFAT support, race condition bug fix */
  //const char *z7file="fe_vtp_z7_streamingv4_Sept2_2026.bin";   /* Fixed fifo full logic    */
  //  const char *z7file="fe_vtp_z7_streamingv4_Sept16_2026.bin";   /* Fixed performance limit bug    */
  //const char *z7file="fe_vtp_z7_streamingv4_Oct20_2026.bin";  /* Fixed UDP Hang bug */
  const char *z7file="fe_vtp_z7_streamingv4_Oct27_2026.bin";  /* Fixed UDP extra ejfat word hang bug*/
  const char *v7file="fe_vtp_v7_fadc_streamingv3_ejfat.bin";      /* EJFAT Support, latest version */



  /* Open VTP library */
  stat = vtpOpen(VTP_FPGA_OPEN | VTP_I2C_OPEN | VTP_SPI_OPEN);
  if(stat < 0)
    {
      printf(" Unable to Open VTP driver library.\n");
    }


  /* Load firmware here */
  sprintf(buf, "/daqfs/coda/VTP/firmware/%s", z7file);
  if(vtpZ7CfgLoad(buf) != OK)
    {
      printf("\n ***ERROR*** Z7 programming failed... (%s)\n", buf);
      ROL_SET_ERROR;
    }

  sprintf(buf, "/daqfs/coda/VTP/firmware/%s", v7file);
  if(vtpV7CfgLoad(buf) != OK)
    {
      printf("\n ***ERROR***V7 programming failed... (%s)\n", buf);
      ROL_SET_ERROR;
    }


  ltm4676_print_status();

}

/**
                        PRESTART
**/
void
rocPrestart()
{
  unsigned int emuip, emuport;
  int ii, stat, ppmask=0;
  int netMode=VTP_NET_MODE; // 0=TCP, 1=UDP
  int localport = 10001; // default local TCP port

  VTPflag = 0;

  /* Initialize the VTP here since external clock is stable now */
  if(vtpInit(VTP_INIT_CLK_VXS_250))
  {
    printf("vtpInit() **FAILED**. User should not continue.\n");
    return;
  }


  printf("Calling VTP_READ_CONF_FILE ..\n");fflush(stdout);

  printf("%s: rol->usrConfig = %s\n", __func__, rol->usrConfig);

  /* Read Config file and Intialize VTP variables */
  vtpInitGlobals();
  if(rol->usrConfig)
    vtpConfig(rol->usrConfig);


  /* Get EB connection info from the ROC to program the VTP TCP stack */
  emuip = vtpRoc_inet_addr(rol->rlinkP->net);
  emuport = rol->rlinkP->port;
  printf("EMU Info from ROC:  IP=0x%08x  port=%d\n",emuip,emuport);
    /* Debug to send VTP data to a specific host/port instead */  
  //emuip   = vtpRoc_inet_addr("129.57.109.232");  /* Debug to indra-s3 */
  emuip   = vtpRoc_inet_addr("129.57.109.230");  /* Debug to indra-s1 */
  emuport = 45100;
  localport = localport + netMode;
  printf("VTP connect info: IP = 0x%08x  Port= %d  Localport = %d\n",emuip, emuport, localport);


  /* Configure all the payload ports - total of 4 FADCs 
     pp_id, ppInfo, moduleID, lag, bank_tag, stream# 
     4 FADCs to Stream 1 and 0 to Stream 2*/
    vtpPayloadConfig(2,ppInfo,1,1,0,1);
    vtpPayloadConfig(4,ppInfo,1,1,0,1);
    vtpPayloadConfig(10,ppInfo,1,1,0,1);
  ppmask = vtpPayloadConfig(12,ppInfo,1,1,0,1);


  /* Update the Streaming EB configuration for the new firmware to get the correct PP Mask and ROCID
     PP mask, nstreams, frame_len (ns), ROCID, ppInfo  */
  vtpStreamingSetEbCfg(ppmask, NUM_VTP_CONNECTIONS, 0xffff, ROCID, ppInfo);
  emuData[4] = ROCID;  /* define ROCID in the EMU Connection data as well*/

  /* If UDP transport then disable cMsg Headers, if EJFAT then enable those headers*/
  if(netMode) {
    vtpStreamingEbDisable(VTP_STREB_CMSG_HDR_EN);
    if(ENABLE_EJFAT) vtpStreamingEbEnable(VTP_STREB_EJFAT_EN);
  }


  /* Disable CMSG Headers if set */
  if(DISABLE_CMSG_HDR) vtpStreamingEbDisable(VTP_STREB_CMSG_HDR_EN);

  /* Enable the Streaming EB to allow Async Events. Disable Stream processing so we can send Prestart */
  stat = vtpStreamingEbEnable(VTP_STREB_ASYNC_FIFO_EN);
  if(stat != OK)
    printf("Error in vtpStreamingEbEnable()\n");

  // Reset the MIG - DDR memory write tagging - for Streaming Ebio 
  vtpStreamingMigReset();

  // Reset the data links between V7 Streaming EB and the Zync TCP client 
  // Set the Network output mode
  vtpStreamingEbioReset(netMode);


  /* Get Stream connection info from file. Then Setup the VTP connection registers manually and connect */
  {
    int inst;
    unsigned char ipaddr[4];
    unsigned char subnet[4];
    unsigned char gateway[4];
    unsigned char mac[6];
    unsigned char udpaddr[4], tcpaddr[4], destip[4];
    unsigned int tcpport, udpport;

    /* fix the destination IP address so it is correct */
    destip[3] = (emuip&0xFF); 
    destip[2] = (emuip&0xFF00)>>8; 
    destip[1] = (emuip&0xFF0000)>>16;
    destip[0] = (emuip&0xFF000000)>>24;

    /* Get the base network port info from the initial Config file */
    vtpStreamingGetNetCfg(
	  0,
          ipaddr,
          subnet,
          gateway,
          mac,
          udpaddr,
	  tcpaddr,
          &udpport,
	  &tcpport
      );

    /* Loop over all connections */
    for (inst=0;inst<NUM_VTP_CONNECTIONS;inst++) { 

      /* Increment the Local IP and MAC address and destination port for each Network connection */
      printf("Stream # %d\n",(inst+1));
      if(inst>0) {
	ipaddr[3] = ipaddr[3] + 1;
	mac[4]    =    mac[4] + 1;
	//emuport   = emuport   + 1;  // Do not bump the port number if you attach to the CODA EMU Aggregator
      }

      printf(" ipaddr=%d.%d.%d.%d\n",ipaddr[0],ipaddr[1],ipaddr[2],ipaddr[3]);
      printf(" subnet=%d.%d.%d.%d\n",subnet[0],subnet[1],subnet[2],subnet[3]);
      printf(" gateway=%d.%d.%d.%d\n",gateway[0],gateway[1],gateway[2],gateway[3]);
      printf(" mac=%02x:%02x:%02x:%02x:%02x:%02x\n",mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
      printf(" udpaddr=%d.%d.%d.%d\n",udpaddr[0],udpaddr[1],udpaddr[2],udpaddr[3]);
      printf(" tcpaddr=%d.%d.%d.%d\n",tcpaddr[0],tcpaddr[1],tcpaddr[2],tcpaddr[3]);
      printf(" udpport=0x%08x  tcpport=0x%08x\n",udpport, tcpport);


      /* Set VTP connection registers */
      vtpStreamingSetNetCfg(
          inst,
	  netMode,
          ipaddr,
          subnet,
          gateway,
          mac,
          destip,
          emuport,
	  localport
      );

      /* Optionally set a new MTU here */
      vtpStreamingSetNetMTU(inst,VTP_TCPIP_MTU_JUMBO);

      /* Read them back one more time */
      vtpStreamingGetNetCfg(
	  inst,
          ipaddr,
          subnet,
          gateway,
          mac,
          udpaddr,
	  tcpaddr,
          &udpport,
	  &tcpport
      );
      printf(" ipaddr=%d.%d.%d.%d\n",ipaddr[0],ipaddr[1],ipaddr[2],ipaddr[3]);
      printf(" subnet=%d.%d.%d.%d\n",subnet[0],subnet[1],subnet[2],subnet[3]);
      printf(" gateway=%d.%d.%d.%d\n",gateway[0],gateway[1],gateway[2],gateway[3]);
      printf(" mac=%02x:%02x:%02x:%02x:%02x:%02x\n",mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
      printf(" udpaddr=%d.%d.%d.%d\n",udpaddr[0],udpaddr[1],udpaddr[2],udpaddr[3]);
      printf(" tcpaddr=%d.%d.%d.%d\n",tcpaddr[0],tcpaddr[1],tcpaddr[2],tcpaddr[3]);
      printf(" udpport=0x%08x  tcpport=0x%08x\n",udpport, tcpport);


      /* Make the Connection - only for Client mode - 
        to disable the cMSg connection data set last parameter 8->0*/
      emuData[7] = inst+1; /* connection number should start at 1 */
      if(DISABLE_CMSG_HDR)
	vtpStreamingTcpConnect(inst, (netMode+1), emuData, 0);
      else
	vtpStreamingTcpConnect(inst, (netMode+1), emuData, 8);
      
      /* Reset the TCP interface and listen for connection requests-in Server mode 
         In UDP mode this will just allow packets to be sent out */
      // vtpStreamingTcpAccept(inst);

    }
  }

  // Send a Prestart Event to each stream
  for(ii=0;ii<NUM_VTP_CONNECTIONS;ii++) {
    vtpStreamingEvioWriteControl(ii,EV_PRESTART,rol->runNumber,rol->runType);
  }


  /* Show VTP-FADC Serial Link Status */
  vtpSerdesStatusAll();


  printf(" Done with User Prestart\n");

}

/**
                        PAUSE
**/
void
rocPause()
{
  VTPflag = 0;
  CDODISABLE(VTP, 1, 0);
}

/**
                        GO
**/
void
rocGo()
{

  int ii, stat;

  if(vtpSerdesCheckLinks() == ERROR)
    {
      daLogMsg("ERROR","VTP Serdes links not up");
    }
  printf("Calling vtpSerdesStatusAll()\n");
  vtpSerdesStatusAll();

  vtpV7SetResetSoft(1);
  vtpV7SetResetSoft(0);
  //  vtpEbResetFifo();


  vtpStats(0);
  vtpSDPrintScalers();

  /*Send Go Event*/
  for(ii=0;ii<NUM_VTP_CONNECTIONS;ii++) {
    vtpStreamingEvioWriteControl(ii,EV_GO,0,0);
  }

  /* Enable StreamingEB Stream processing */
  stat = vtpStreamingEbEnable(VTP_STREB_PP_STREAM_EN);
  if(stat != OK)
    printf("Error in vtpStreamingEbEnable()\n");

  /* Enable to recieve Triggers */
  CDOENABLE(VTP, 1, 0);
  VTPflag=0; /* disable polling for triggers in streaming mode */
}

/**
                        END
**/
void
rocEnd()
{
  int ii, stat, status;
  unsigned int nFrames;

  VTPflag = 0;
  CDODISABLE(VTP, 1, 0);

  /* The Master ROC should already have disabled streams by now */
  vtpStats(0);

  sleep(2);  /* wit a bit to make sure the VTP sends all its data */

  /* Send an End Event */
  /* Enable StreamingEB AsyncFiFo processing so we can send the End Event*/
  stat = vtpStreamingEbEnable(VTP_STREB_ASYNC_FIFO_EN);
  if(stat != OK)
    printf("Error in vtpStreamingEbEnable()\n");

  /*Send End Event to all streams*/
  for(ii=0;ii<NUM_VTP_CONNECTIONS;ii++) {
    nFrames = vtpStreamingFramesSent(ii);
    vtpStreamingEvioWriteControl(ii,EV_END,rol->runNumber,nFrames);
    printf("rocEnd: Stream %d - Wrote End Event (total %d frames)\n",ii, nFrames);
  }
  sleep(2);

  /* Disable Streaming EB - careful. If the User Sync is not high this can drop packets from a frame using UDP */
  //  vtpStreamingEbReset();
  /* Try just disabling the Stream inputs instead - Doing a full reset also zeros frame counters */
  /*  stat = vtpStreamingEbDisable(VTP_STREB_PP_STREAM_EN);
  if(stat != OK)
    printf("Error in vtpStreamingEbDisable()\n");
  */


  /* Disconnect the Socket - Client Mode TCP connections */
  for(ii=0;ii<NUM_VTP_CONNECTIONS;ii++) {
    status = vtpStreamingTcpConnect(ii,0,0,0);
    if(status == ERROR) {
      printf("rocEnd: Error closing socket on link %d\n",ii);
    }
  }
  
  /* Reset all Socket Connections on the TCP Server - Server Mode only*/
  vtpStreamingTcpReset(0);


  vtpSDPrintScalers();
  //  vtpTiLinkStatus();
}

/**
                        READOUT
**/
void
rocTrigger(int EVTYPE)
{

/* This routine is not available for VTP Streaming mode firmware */

}

/**
                        READOUT ACKNOWLEDGE
**/
void
rocTrigger_done()
{
  /* If No TI to acknowlege in Streaming mode set code = 1 */
  CDOACK(VTP, 1, 0);
}

/**
                        RESET
**/
void
rocReset()
{



  /* close VTP device */
  vtpClose(VTP_FPGA_OPEN|VTP_I2C_OPEN|VTP_SPI_OPEN);
}


/*
  Local Variables:
  compile-command: "make -k vtp_list.so"
  End:
 */

